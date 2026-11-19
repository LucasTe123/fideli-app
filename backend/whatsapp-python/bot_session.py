"""A WhatsApp client, credentials and conversation state per verified business."""
from __future__ import annotations
import asyncio
import hashlib
import json
import logging
import os
import re
import time
import unicodedata
import urllib.request
from uuid import uuid4
from pathlib import Path
from typing import Any
from piwapp import AuthenticationCreds, Client, ConnectionConfig
from piwapp.events import WAEventType
from business_settings import SettingsStore, save_json
from business_auth import public_products
from gemini_bot import GeminiError, generate_business_reply
from signal_compat import install
from whatsapp_delivery import install as install_delivery, DeliveryError
from piwapp.binary.jids import jid_normalized_user

install()
install_delivery()


def latest_version():
    request = urllib.request.Request('https://web.whatsapp.com/sw.js', headers={
        'sec-fetch-site': 'none', 'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
    })
    try:
        with urllib.request.urlopen(request, timeout=4) as response:
            # WhatsApp's service worker publishes this revision as a regular
            # JSON key. Accept an optional escaped quote too, but keep the
            # whitespace and digits as regex tokens (not literal backslashes).
            match = re.search(
                r'client_revision.{0,4}:\s*(\d+)',
                response.read().decode('utf-8', 'replace'),
            )
        if match:
            return (2, 3000, int(match.group(1)))
    except (OSError, ValueError):
        pass
    return (2, 3000, 1051464192)


def normalized(text):
    return ''.join(c for c in unicodedata.normalize('NFD', text.lower()) if unicodedata.category(c) != 'Mn')


class ObservedClient(Client):
    def __init__(self, *args, session, **kwargs):
        super().__init__(*args, **kwargs)
        self.owner = session

    def _wire(self, conn):
        super()._wire(conn)
        original = conn._on_node
        original_pair_device = conn._on_pair_device
        original_pair_success = conn._on_pair_success
        qr_task = None

        def cancel_qr():
            nonlocal qr_task
            if qr_task is not None:
                qr_task.cancel()
                qr_task = None

        async def rotate_qr():
            # WhatsApp gives a batch of refs: first lives 60s, subsequent 20s.
            await asyncio.sleep(60)
            while not conn.creds.me and not conn._closed.is_set():
                if not conn._qr_refs:
                    self.owner.state.update(qr=None, status='connecting')
                    conn._bg_tasks.discard(asyncio.current_task())
                    await conn._fail(408)
                    return
                await conn._emit_next_qr()
                await asyncio.sleep(20)

        async def pair_device(stanza):
            nonlocal qr_task
            cancel_qr()
            await original_pair_device(stanza)
            qr_task = asyncio.create_task(rotate_qr())
            conn._bg_tasks.add(qr_task)
            qr_task.add_done_callback(conn._bg_tasks.discard)

        async def pair_success(stanza):
            cancel_qr()
            await original_pair_success(stanza)

        conn._on_pair_device = pair_device
        conn._on_pair_success = pair_success

        async def receive(node):
            try:
                await original(node)
            except Exception as error:
                known = {'invalid account signature HMAC', 'failed to verify account signature', 'missing device-identity or device in pair-success'}
                detail = str(error) if str(error) in known else type(error).__name__
                self.owner.state.update(status='error', qr=None, error=f'No se pudo confirmar el enlace: {detail}')
                self._running = False
                raise
        conn._on_node = receive


class BotSession:
    def __init__(self, folder: Path, business: dict, registry: dict):
        self.folder = folder
        self.settings = SettingsStore(folder, business)
        self.business = business
        self.registry = registry
        self.client = None
        self.task = None
        self.reply_tasks: set[asyncio.Task] = set()
        self.lock = asyncio.Lock()
        self.seen: set[str] = set()
        self.peer_aliases = {}
        self.started_at = time.time()
        self.products_at = 0.0
        self.products = []
        self.state = dict(status='idle', qr=None, error=None, pairing_confirmed=False,
                          messages_received=0, test_replies_sent=0, ai_replies_sent=0,
                          ai_error=None, ai_status='ready', last_disconnect_reason=None, decrypt_errors=0, outbound_accepted=0)

    def refresh_business(self, business):
        self.business = business
        self.settings.business = business
        self.settings.data['profile'] = business
        self.settings.save()

    def save_auth(self, creds):
        save_json(self.folder / 'account.json', json.loads(creds.to_json()))

    def load_auth(self):
        path = self.folder / 'account.json'
        if path.exists():
            return AuthenticationCreds.from_json(path.read_text())
        creds = AuthenticationCreds.initial()
        self.save_auth(creds)
        return creds

    def update_status(self, update):
        if update.get('connection') or update.get('qr'):
            logging.getLogger('uvicorn.error').info(
                'WhatsApp connection=%s reason=%s logged_out=%s qr_updated=%s',
                update.get('connection'), update.get('reason'),
                bool(update.get('logged_out')), bool(update.get('qr')))
        if update.get('logged_out'):
            reason = update.get('reason')
            self.state.update(status='disconnected', qr=None, pairing_confirmed=False,
                last_disconnect_reason=reason,
                error=None if reason == 401 else 'WhatsApp rechazó la conexión. Intenta vincular de nuevo.')
            return
        if self.state['status'] == 'error' and self.state['error']:
            return
        if update.get('error'):
            self.state.update(error='No se pudo establecer la conexión con WhatsApp.', qr=None, status='error')
            return
        if update.get('connection') == 'close':
            self.state['last_disconnect_reason'] = update.get('reason')
        if update.get('qr'):
            self.state.update(qr=str(update['qr']), status='pairing', pairing_confirmed=False, error=None)
        elif update.get('connection') == 'open':
            me = self.client.creds.me if self.client else None
            account = me.id.split('@')[0].split(':')[0] if me else ''
            fingerprint = hashlib.sha256(account.encode()).hexdigest() if account else ''
            if fingerprint and any(s is not self and s.settings.data.get('account_fingerprint') == fingerprint for s in self.registry.values()):
                self.state.update(status='error', qr=None, error='Este WhatsApp ya está vinculado a otro negocio de Fideli.')
                if self.client:
                    asyncio.create_task(self.client.stop())
                return
            self.settings.data['account_fingerprint'] = fingerprint
            self.settings.save()
            self.state.update(qr=None, status='connected', pairing_confirmed=True, error=None)
        elif update.get('connection') in ('connecting', 'close', 'reconnecting'):
            self.state.update(qr=None, status='confirming' if self.state['pairing_confirmed'] else 'connecting')

    def pairing_success(self, _):
        self.state.update(qr=None, pairing_confirmed=True, status='confirming', error=None)

    def renew_revoked_auth(self):
        # Keep a private recovery copy; settings and images remain in place.
        backup = self.folder / 'revoked-sessions' / uuid4().hex
        backup.mkdir(parents=True, mode=0o700)
        for name in ('account.json', 'account.json.keys'):
            path = self.folder / name
            if path.exists():
                path.replace(backup / name)
        self.save_auth(AuthenticationCreds.initial())
        self.settings.data.pop('account_fingerprint', None)
        self.settings.save()
        self.seen.clear()
        self.peer_aliases.clear()

    async def reset_link(self):
        """Forget the saved device link while retaining a private recovery copy."""
        await self.stop()
        self.renew_revoked_auth()
        self.state.update(
            status='idle', qr=None, error=None, pairing_confirmed=False,
            last_disconnect_reason=None,
        )

    async def run(self):
        try:
            version = await asyncio.to_thread(latest_version)
            for attempt in range(2):
                self.state['last_disconnect_reason'] = None
                self.client = ObservedClient(self.load_auth(), ConnectionConfig(version=version),
                    session=self, on_creds_update=self.save_auth, keys_path=str(self.folder / 'account.json.keys'), db_path=None)
                self.client.on('connection.update', self.update_status)
                self.client.on('pairing.success', self.pairing_success)
                self.client.on('frame', self.on_frame)
                self.client.events.on(WAEventType.MESSAGES_UPDATE, self.on_message_update)
                self.client.events.on(WAEventType.MESSAGES_UPSERT, self.on_messages)
                await self.client.start()
                if self.state['last_disconnect_reason'] != 401:
                    break
                await self.client.stop()
                for task in list(self.reply_tasks):
                    task.cancel()
                if self.reply_tasks:
                    await asyncio.gather(*self.reply_tasks, return_exceptions=True)
                self.renew_revoked_auth()
                self.state.update(status='starting', qr=None, error=None, pairing_confirmed=False)
                if attempt == 1:
                    self.state.update(status='error', error='WhatsApp cerró la sesión. Pulsa Vincular WhatsApp para generar otro QR.')
            if self.state['status'] not in ('error', 'connected', 'pairing'):
                self.state['status'] = 'idle'
        except asyncio.CancelledError:
            raise
        except Exception:
            self.state.update(qr=None, status='error', error='No se pudo iniciar WhatsApp. Intenta conectar de nuevo.')
        finally:
            self.client = None

    def start(self):
        if self.task and not self.task.done():
            return
        self.settings.data['auto_start'] = True
        self.settings.save()
        self.started_at = time.time()
        self.state.update(status='starting', qr=None, error=None, pairing_confirmed=False)
        self.task = asyncio.create_task(self.run())

    async def stop(self, persist=True):
        if persist:
            self.settings.data['auto_start'] = False
            self.settings.save()
        for task in list(self.reply_tasks):
            task.cancel()
        if self.reply_tasks:
            await asyncio.gather(*self.reply_tasks, return_exceptions=True)
        if self.client:
            await self.client.stop()
        if self.task and not self.task.done():
            self.task.cancel()
            await asyncio.gather(self.task, return_exceptions=True)
        self.state.update(qr=None, status='idle', pairing_confirmed=False)

    def on_frame(self, node):
        if node.tag == 'ack' and node.attrs.get('class') == 'message' and node.attrs.get('error') in (None, '', '0', 0):
            self.state['outbound_accepted'] += 1
        if node.tag != 'message':
            return
        sender = jid_normalized_user(node.attrs.get('from'))
        pn = jid_normalized_user(node.attrs.get('sender_pn'))
        if sender.endswith('@lid') and pn.endswith('@s.whatsapp.net'):
            self.peer_aliases[sender] = pn

    def on_message_update(self, payload):
        if isinstance(payload, dict) and payload.get('decryptError'):
            self.state['decrypt_errors'] += 1
            self.state['ai_error'] = 'Llegó un mensaje, pero WhatsApp no pudo descifrarlo en el dispositivo vinculado.'

    def on_messages(self, payload):
        if str(getattr(getattr(payload, 'type', None), 'value', getattr(payload, 'type', ''))).lower() == 'append':
            return
        messages = getattr(payload, 'messages', None) or []
        for message in messages:
            if isinstance(message, dict) and not (message.get('key') or {}).get('fromMe') and message.get('text'):
                if not (message.get('key') or {}).get('remoteJid', '').endswith(('@s.whatsapp.net', '@lid')):
                    continue
                # A later successfully decrypted message means the linked
                # device is working; don't leave an earlier one-off decrypt
                # failure pinned on the connection screen.
                self.state['ai_error'] = None
                self.state['messages_received'] += 1
                task = asyncio.create_task(self.reply(message))
                self.reply_tasks.add(task)
                task.add_done_callback(self.reply_tasks.discard)

    async def send_images(self, chat_id, ids):
        allowed = {m['id']: m for m in self.settings.data.get('media', []) if m.get('enabled', True)}
        for mid in list(dict.fromkeys(ids))[:2]:
            if mid not in allowed or not self.client or not self.settings.data.get('enabled'):
                continue
            item = allowed[mid]
            await self.client.send_media(chat_id, self.settings.image_path(mid).read_bytes(),
                                         mimetype='image/jpeg', media_type='image', caption=item.get('caption') or item['title'])

    async def reply(self, message):
        settings = self.settings.data
        if not self.client or self.state['status'] != 'connected' or not settings.get('enabled'):
            return
        key = message.get('key') or {}
        chat_id = key.get('remoteJid', '')
        text = (message.get('text') or '').strip()
        if key.get('fromMe') or not chat_id.endswith(('@s.whatsapp.net', '@lid')) or not text:
            return
        if text.lower().startswith('!fideli'):
            text = text[7:].strip() or 'Hola'
        try:
            stamp = float(message.get('messageTimestamp') or 0)
            if stamp < max(int(self.started_at) - 1, time.time() - 120) or stamp > time.time() + 60:
                return
        except (ValueError, TypeError):
            return
        mid = str(key.get('id') or '')
        if not mid or mid in self.seen:
            return
        self.seen.add(mid)
        if len(self.seen) > 2000:
            self.seen = {mid}
        if len(self.reply_tasks) > 20:
            return
        chat_id = self.peer_aliases.get(jid_normalized_user(chat_id), jid_normalized_user(chat_id))
        async with self.lock:
            if not self.client or self.state['status'] != 'connected' or not self.settings.data.get('enabled'):
                return
            settings = self.settings.view()
            images = [m for m in settings['media'] if m.get('enabled', True)]
            try:
                greeting = normalized(text) in ('hola', 'buenas', 'buenos dias', 'buenas tardes', 'buenas noches', 'hello', 'hi')
                welcome_images = []
                if settings['welcome_enabled']:
                    self.state.update(ai_status='sending', ai_error=None)
                    welcome = settings['welcome_message'].replace('{negocio}', self.business['name']).replace('{catalogo}', '')
                    await self.client.send_text(chat_id, welcome.strip() or f"¡Hola! Bienvenido a {self.business['name']}.")
                    welcome_images = [m['id'] for m in images if m.get('send_on_welcome')][:2]
                if settings['catalog_enabled']:
                    self.state['ai_status'] = 'sending'
                    catalog = settings.get('catalog_message', 'Te pasamos nuestro catálogo:').replace('{negocio}', self.business['name']).replace('{catalogo}', settings['catalog_url'])
                    if settings['catalog_url'] not in catalog:
                        catalog += '\n' + settings['catalog_url']
                    await self.client.send_text(chat_id, catalog.strip())
                await self.send_images(chat_id, welcome_images)
                if greeting or (settings['catalog_enabled'] and any(word in normalized(text) for word in ('catalogo', 'link de la tienda', 'enlace de la tienda', 'ver productos', 'menu'))):
                    self.state.update(ai_status='ready', ai_error=None)
                    self.state['test_replies_sent'] += 1
                    return
                if settings['catalog_enabled'] and any(word in normalized(text) for word in ('catalogo', 'link de la tienda', 'enlace de la tienda', 'ver productos', 'menu')):
                    result = {'reply': f"Aquí tienes el catálogo de {self.business['name']}: {settings['catalog_url']}", 'image_ids': []}
                else:
                    self.state.update(ai_status='generating', ai_error=None)
                    if time.monotonic() - self.products_at > 60:
                        self.products = await asyncio.to_thread(public_products, self.business)
                        self.products_at = time.monotonic()
                    context = dict(business_name=self.business['name'], category=self.business.get('category', ''),
                        branches=self.business.get('branches', []), products=self.products,
                        catalog_url=settings['catalog_url'] if settings['catalog_enabled'] else '',
                        instructions=settings['instructions'], images=[{k: m.get(k) for k in ('id','title','caption','keywords')} for m in images])
                    result = await asyncio.to_thread(generate_business_reply, text, context)
                    self.state['ai_replies_sent'] += 1
                if not self.client or not self.settings.data.get('enabled') or self.state['status'] != 'connected':
                    return
                self.state['ai_status'] = 'sending'
                await self.client.send_text(chat_id, result['reply'])
                await self.send_images(chat_id, [i for i in result['image_ids'] if i not in welcome_images])
                self.state['ai_error'] = None
                self.state['ai_status'] = 'ready'
                self.state['test_replies_sent'] += 1
            except DeliveryError as error:
                self.state.update(ai_error=str(error), ai_status='error')
            except GeminiError as error:
                self.state['ai_error'] = str(error)
                self.state['ai_status'] = 'error'
                if self.client and self.state['status'] == 'connected':
                    try:
                        await self.client.send_text(chat_id, f"Ahora no puedo responder esa consulta. Puedes consultar nuestro catálogo: {settings['catalog_url']}" if settings['catalog_enabled'] else 'Ahora no puedo responder. Intenta más tarde.')
                    except Exception:
                        pass
            except Exception:
                self.state['ai_error'] = 'No se pudo enviar una respuesta o imagen por WhatsApp.'
                self.state['ai_status'] = 'error'
