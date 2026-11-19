from __future__ import annotations

import asyncio
import json
import os
import shutil
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse
from pydantic import BaseModel, Field

from business_auth import require_business, public_products
from business_settings import SettingsInput, MediaInput, MediaUpload, save_json
from bot_session import BotSession
from gemini_bot import api_key, MODEL, generate_business_reply, GeminiError

ROOT = Path(__file__).resolve().parent
STATE_DIR = Path(os.environ.get('FIDELI_WHATSAPP_STATE_DIR', ROOT / 'state'))
sessions: dict[str, BotSession] = {}
registry_lock = asyncio.Lock()


def migrate_legacy(business: dict, session: BotSession):
    """Migrate only to an explicitly bound, verified Fideli account ID."""
    legacy = STATE_DIR / 'account.json'
    marker = STATE_DIR / 'legacy-owner.json'
    expected = os.environ.get('FIDELI_LEGACY_BUSINESS_ID')
    if marker.exists():
        expected = json.loads(marker.read_text()).get('business_id')
    if not expected or business['id'] != expected or not legacy.exists():
        return
    if not marker.exists():
        save_json(marker, {'business_id': business['id']})
    if (session.folder / 'account.json').exists():
        return
    session.folder.mkdir(parents=True, exist_ok=True, mode=0o700)
    for filename in ('account.json', 'account.json.keys'):
        source = STATE_DIR / filename
        if source.exists():
            destination = session.folder / filename
            shutil.copyfile(source, destination)
            os.chmod(destination, 0o600)
    session.settings.data['auto_start'] = True
    session.settings.save()


async def tenant(business: dict = Depends(require_business)) -> BotSession:
    async with registry_lock:
        uid = business['id']
        if uid not in sessions:
            session = BotSession(STATE_DIR / 'tenants' / uid, business, sessions)
            sessions[uid] = session
        session = sessions[uid]
        migrate_legacy(business, session)
        if session.settings.data.get('auto_start') and session.task is None:
            session.start()
        if session.business != business or not session.settings.data.get('profile'):
            session.refresh_business(business)
        return session


@asynccontextmanager
async def lifespan(app):
    # Restore each previously linked tenant independently, with its last verified profile.
    for path in (STATE_DIR / 'tenants').glob('*/config.json'):
        data = json.loads(path.read_text())
        profile = data.get('profile')
        if profile and profile.get('id') == path.parent.name:
            sessions[profile['id']] = BotSession(path.parent, profile, sessions)
    for session in sessions.values():
        if session.settings.data.get('auto_start'):
            session.start()
    yield
    await asyncio.gather(*(s.stop(persist=False) for s in sessions.values()), return_exceptions=True)


app = FastAPI(title='Fideli WhatsApp Connector', docs_url=None, redoc_url=None, lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origin_regex=r'^https?://(localhost|127\.0\.0\.1)(:\d+)?$',
                   allow_methods=['GET','POST','PUT','PATCH','DELETE'], allow_headers=['content-type','authorization'])


@app.middleware('http')
async def size_limit(request: Request, call_next):
    try:
        if int(request.headers.get('content-length', '0')) > 2700000:
            return JSONResponse({'detail': 'La imagen es demasiado grande.'}, status_code=413)
    except ValueError:
        return JSONResponse({'detail': 'Solicitud inválida.'}, status_code=400)
    return await call_next(request)


@app.get('/health')
async def health():
    return {'status':'ok'}


@app.get('/api/whatsapp/{business_id}/status')
async def status(session: BotSession = Depends(tenant)):
    return {**session.state, 'business_id': session.business['id'], 'business_name': session.business['name'],
            'ai_ready': bool(api_key()), 'ai_model': MODEL, 'bot_enabled': session.settings.data['enabled']}


@app.post('/api/whatsapp/{business_id}/start', status_code=202)
async def start(session: BotSession = Depends(tenant)):
    session.start()
    return {'status':session.state['status']}


@app.post('/api/whatsapp/{business_id}/stop')
async def stop(session: BotSession = Depends(tenant)):
    await session.stop()
    return {'status':'idle'}


@app.post('/api/whatsapp/{business_id}/reset-link')
async def reset_link(session: BotSession = Depends(tenant)):
    await session.reset_link()
    return {'status':'idle', 'link_reset':True}


@app.get('/api/whatsapp/{business_id}/settings')
async def settings(session: BotSession = Depends(tenant)):
    return session.settings.view()


@app.put('/api/whatsapp/{business_id}/settings')
async def save_settings(settings: SettingsInput, session: BotSession = Depends(tenant)):
    return session.settings.update(settings)


@app.post('/api/whatsapp/{business_id}/media', status_code=201)
async def upload_image(media: MediaUpload, session: BotSession = Depends(tenant)):
    return session.settings.add_image(media)


@app.get('/api/whatsapp/{business_id}/media/{media_id}')
async def image(media_id: str, session: BotSession = Depends(tenant)):
    path = session.settings.image_path(media_id)
    if not path.exists():
        raise HTTPException(404, 'Imagen no encontrada.')
    return FileResponse(path, media_type='image/jpeg', headers={'Cache-Control':'private, no-store'})


@app.patch('/api/whatsapp/{business_id}/media/{media_id}')
async def update_image(media_id: str, media: MediaInput, session: BotSession = Depends(tenant)):
    session.settings.update_image(media_id, media)
    return {'status':'saved'}


@app.delete('/api/whatsapp/{business_id}/media/{media_id}')
async def remove_image(media_id: str, session: BotSession = Depends(tenant)):
    session.settings.remove_image(media_id)
    return {'status':'removed'}


class PreviewInput(BaseModel):
    prompt: str = Field(min_length=1, max_length=4000)


@app.post('/api/whatsapp/{business_id}/preview')
async def preview(body: PreviewInput, session: BotSession = Depends(tenant)):
    settings = session.settings.view()
    context = dict(business_name=session.business['name'], category=session.business.get('category',''),
        branches=session.business.get('branches', []), products=await asyncio.to_thread(public_products, session.business),
        catalog_url=settings['catalog_url'] if settings['catalog_enabled'] else '', instructions=settings['instructions'],
        images=[{k:m.get(k) for k in ('id','title','caption','keywords')} for m in settings['media'] if m.get('enabled',True)])
    try:
        return await asyncio.to_thread(generate_business_reply, body.prompt, context)
    except GeminiError as error:
        raise HTTPException(502, str(error)) from None
