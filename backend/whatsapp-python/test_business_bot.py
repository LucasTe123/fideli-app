import asyncio
import base64
import io
import json
import tempfile
import time
from types import SimpleNamespace
import unittest
from pathlib import Path
from unittest.mock import patch
from uuid import uuid4

from fastapi import HTTPException
from PIL import Image
from pydantic import ValidationError
import business_auth
import app
from business_settings import SettingsStore, SettingsInput, MediaUpload
from bot_session import BotSession
from gemini_bot import generate_business_reply


def business(name):
    return {'id': str(uuid4()), 'name': name, 'public_slug': name.lower(), 'category': '', 'products': []}


def photo():
    data = io.BytesIO()
    Image.new('RGB', (10, 10), 'green').save(data, format='JPEG')
    return base64.b64encode(data.getvalue()).decode()


class Recorder:
    def __init__(self): self.texts, self.images = [], []
    async def send_text(self, jid, text): self.texts.append((jid, text))
    async def send_media(self, jid, data, **kwargs): self.images.append((jid, data, kwargs))


class SettingsTests(unittest.TestCase):
    def test_independent_settings_and_media_ownership(self):
        with tempfile.TemporaryDirectory() as folder:
            a = SettingsStore(Path(folder) / 'a', business('Padelbo'))
            b = SettingsStore(Path(folder) / 'b', business('Tartina'))
            a.update(SettingsInput(welcome_message='Bienvenido a {negocio}', instructions='Atención de Padelbo'))
            image = a.add_image(MediaUpload(title='Cancha', data=photo()))
            self.assertEqual(a.view()['catalog_url'], 'https://padelbo.fideli.site/tienda')
            self.assertEqual(b.view()['catalog_url'], 'https://tartina.fideli.site/tienda')
            self.assertEqual(b.data['instructions'], '')
            with self.assertRaises(HTTPException): b.image_path(image['id'])
            restored = SettingsStore(Path(folder) / 'a', a.business)
            self.assertEqual(restored.data['instructions'], 'Atención de Padelbo')
            a.remove_image(image['id'])
            with self.assertRaises(HTTPException): a.image_path(image['id'])
            self.assertTrue((a.folder / 'media' / (image['id'] + '.jpg')).exists())

    def test_invalid_content_and_urls_rejected(self):
        with self.assertRaises(ValidationError): SettingsInput(welcome_message='hola', catalog_url='javascript:alert(1)')
        with self.assertRaises(ValidationError): SettingsInput(welcome_message=' ')
        with tempfile.TemporaryDirectory() as folder:
            store = SettingsStore(Path(folder), business('Padelbo'))
            with self.assertRaises(HTTPException): store.add_image(MediaUpload(title='fake', data=base64.b64encode(b'not an image').decode()))

    def test_model_cannot_select_other_business_images(self):
        context = {'business_name':'Padelbo', 'images':[{'id':'allowed'}]}
        with patch('gemini_bot.generate_reply', return_value=json.dumps({'reply':'Hola', 'image_ids':['tartina-photo','allowed','allowed']})):
            self.assertEqual(generate_business_reply('foto', context)['image_ids'], ['allowed'])

    def test_legacy_session_requires_explicit_owner_id(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(app, 'STATE_DIR', Path(folder)):
            (Path(folder) / 'account.json').write_text('{}')
            b = business('Padelbo')
            session = BotSession(Path(folder) / 'tenants' / b['id'], b, {})
            with patch.dict('os.environ', {}, clear=True): app.migrate_legacy(b, session)
            self.assertFalse((session.folder / 'account.json').exists())
            (Path(folder) / 'legacy-owner.json').write_text(json.dumps({'business_id':b['id']}))
            app.migrate_legacy(b, session)
            self.assertTrue((session.folder / 'account.json').exists())


class TenantAuthTests(unittest.IsolatedAsyncioTestCase):
    async def test_bearer_identity_must_match_requested_business(self):
        business_auth._cache.clear()
        a, b = business('Padelbo'), business('Tartina')
        with patch('business_auth._verify', return_value=a):
            self.assertEqual((await business_auth.require_business(a['id'], 'Bearer token'))['id'], a['id'])
            with self.assertRaises(HTTPException) as result: await business_auth.require_business(b['id'], 'Bearer token')
            self.assertEqual(result.exception.status_code, 403)
        with self.assertRaises(HTTPException) as result: await business_auth.require_business(a['id'], None)
        self.assertEqual(result.exception.status_code, 401)
        business_auth._cache.clear()

    async def test_two_consecutive_questions_are_not_silently_discarded(self):
        with tempfile.TemporaryDirectory() as folder:
            session = BotSession(Path(folder), business('Padelbo'), {})
            session.client = Recorder()
            session.state['status'] = 'connected'
            session.settings.data.update(welcome_enabled=False, catalog_enabled=False)
            with patch('bot_session.public_products', return_value=[]), patch('bot_session.generate_business_reply', return_value={'reply':'Respuesta real del adaptador', 'image_ids':[]}):
                for mid in ('first','second'):
                    await session.reply({'key':{'id':mid, 'remoteJid':'test@s.whatsapp.net'}, 'text':'!fideli ¿qué vendes?', 'messageTimestamp':time.time()})
            self.assertEqual(len(session.client.texts), 2)
            self.assertEqual(session.state['ai_status'], 'ready')

    async def test_each_message_gets_welcome_then_separate_catalog_without_gemini(self):
        with tempfile.TemporaryDirectory() as folder:
            session = BotSession(Path(folder), business('Padelbo'), {})
            session.client = Recorder()
            session.state['status'] = 'connected'
            with patch('bot_session.generate_business_reply') as generate:
                for mid in ('one', 'two'):
                    await session.reply({'key':{'id':mid, 'remoteJid':'test@s.whatsapp.net'}, 'text':'hola', 'messageTimestamp':time.time()})
                generate.assert_not_called()
            self.assertEqual(len(session.client.texts), 4)
            self.assertEqual(session.client.texts[0][1], '¡Hola! Bienvenido a Padelbo.')
            self.assertEqual(session.client.texts[2][1], session.client.texts[0][1])
            self.assertEqual(session.client.texts[1][1], 'Te pasamos nuestro catálogo:\nhttps://padelbo.fideli.site/tienda')
            self.assertEqual(session.client.texts[3][1], session.client.texts[1][1])

    async def test_disabled_catalog_is_not_expanded_in_welcome(self):
        with tempfile.TemporaryDirectory() as folder:
            session = BotSession(Path(folder), business('Padelbo'), {})
            session.client = Recorder()
            session.state['status'] = 'connected'
            session.settings.data.update(catalog_enabled=False, welcome_message='Hola desde {negocio}. {catalogo}')
            await session.reply({'key':{'id':'new', 'remoteJid':'test@s.whatsapp.net'}, 'text':'hola', 'messageTimestamp':time.time()})
            self.assertEqual(session.client.texts[0][1], 'Hola desde Padelbo.')

    async def test_same_whatsapp_account_cannot_attach_to_two_businesses(self):
        with tempfile.TemporaryDirectory() as folder:
            registry = {}
            for index, name in enumerate(('Padelbo', 'Tartina')):
                profile = business(name)
                session = BotSession(Path(folder) / name, profile, registry)
                registry[profile['id']] = session
                recorder = Recorder()
                recorder.creds = SimpleNamespace(me=SimpleNamespace(id=f'demo:{index}@s.whatsapp.net'))
                async def stop(): pass
                recorder.stop = stop
                session.client = recorder
                session.update_status({'connection':'open'})
            a, b = list(registry.values())
            self.assertEqual(a.state['status'], 'connected')
            self.assertEqual(b.state['status'], 'error')
            self.assertIn('otro negocio', b.state['error'])
            await asyncio.sleep(0)

    async def test_welcome_and_images_are_scoped_and_history_is_ignored(self):
        with tempfile.TemporaryDirectory() as folder:
            registry = {}
            for name in ('Padelbo','Tartina'):
                profile = business(name)
                session = BotSession(Path(folder) / name, profile, registry)
                registry[profile['id']] = session
                session.client = Recorder()
                session.state['status'] = 'connected'
                image = session.settings.add_image(MediaUpload(title=name, data=photo(), send_on_welcome=True))
                message = {'key':{'id':name, 'remoteJid':'test@s.whatsapp.net'}, 'text':'hola', 'messageTimestamp':time.time()}
                await session.reply(message)
                self.assertIn(name, session.client.texts[0][1])
                self.assertIn(f'https://{name.lower()}.fideli.site/tienda', session.client.texts[1][1])
                self.assertEqual(len(session.client.images), 1)
                self.assertEqual(session.client.images[0][2]['caption'], name)
                count = len(session.client.texts)
                message['key']['id'] = 'old'
                message['messageTimestamp'] = session.started_at - 180
                await session.reply(message)
                self.assertEqual(len(session.client.texts), count)
            a, b = list(registry.values())
            a.settings.data.update(welcome_enabled=False, catalog_enabled=False)
            a.client.texts.clear()
            a.client.images.clear()
            with patch('bot_session.public_products', return_value=[]), patch('bot_session.generate_business_reply', return_value={'reply':'Padelbo','image_ids':[b.settings.data['media'][0]['id']]}) as generate:
                await a.reply({'key':{'id':'query','remoteJid':'test@s.whatsapp.net'}, 'text':'Quiero una foto de la cancha', 'messageTimestamp':time.time()})
                self.assertEqual(generate.call_args.args[1]['business_name'],'Padelbo')
                self.assertEqual(len(a.client.images),0)


if __name__ == '__main__': unittest.main()
