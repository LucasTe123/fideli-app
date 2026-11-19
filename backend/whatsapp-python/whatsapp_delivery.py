"""Checked WhatsApp DM delivery: never silently skip encrypted recipients."""
from piwapp.binary import BinaryNode, jid_decode, jid_encode
from piwapp.binary.jids import jid_normalized_user
from piwapp.api import messages_send as ms
from piwapp.api.messages import encode_wa_message
from piwapp.crypto.double_ratchet import SessionCipher
from piwapp.crypto import signal_curve
from piwapp.socket.connection import Connection
from piwapp.utils import generate_message_tag


class DeliveryError(Exception):
    pass


def participant_nodes(store, message, devices, extra_attrs=None):
    nodes = []
    include_identity = False
    plaintext = encode_wa_message(message)
    for jid in devices:
        try:
            kind, encrypted = SessionCipher(store, jid).encrypt(plaintext)
        except Exception:
            raise DeliveryError('WhatsApp no pudo cifrar la respuesta para un dispositivo del chat.') from None
        attrs = {'v':'2', 'type':'pkmsg' if kind == 3 else 'msg', **(extra_attrs or {})}
        include_identity = include_identity or kind == 3
        nodes.append(BinaryNode(tag='to', attrs={'jid':jid}, content=[BinaryNode(tag='enc', attrs=attrs, content=encrypted)]))
    return nodes, include_identity


async def relay_dm(self, to_jid, message, msg_id, *, stanza_attrs=None, enc_attrs=None):
    me = self.creds.me
    recipient = jid_normalized_user(to_jid)
    own = jid_normalized_user(me.id)
    own_jids = {own, jid_normalized_user(getattr(me,'lid', None))}
    result = await self.query(ms.build_usync_query([own, recipient], generate_message_tag()))
    devices = ms.parse_usync_devices(result)
    targets = [d for d in devices if d != me.id]
    recipient_devices = [d for d in targets if jid_normalized_user(d) == recipient]
    own_devices = [d for d in targets if jid_normalized_user(d) in own_jids]
    if not recipient_devices:
        raise DeliveryError('WhatsApp no encontró dispositivos del destinatario para enviar la respuesta.')
    need = [d for d in recipient_devices + own_devices if not self.signal_store.contains_session(d)]
    if need:
        bundles = ms.parse_prekey_bundles(await self.query(ms.build_prekey_fetch(need, generate_message_tag())))
        for bundle in bundles.values():
            signed = bundle['signedPreKey']
            if not signal_curve.verify_signature(bundle['identityKey'], signed['publicKey'], signed['signature']):
                raise DeliveryError('WhatsApp no pudo validar las claves de un dispositivo del destinatario.')
        ms.inject_sessions(self.signal_store, bundles)
    other_nodes, other_identity = participant_nodes(self.signal_store, message, recipient_devices, enc_attrs)
    own_nodes, own_identity = participant_nodes(self.signal_store, ms.dsm_message(recipient, message), own_devices, enc_attrs)
    stanza = ms.build_message_stanza(msg_id, recipient, other_nodes + own_nodes,
        include_device_identity=other_identity or own_identity, creds=self.creds, extra_attrs=stanza_attrs)
    # query registers the ID before sending; the socket reader resolves it on
    # the server ack. Returning from a socket write alone is not delivery.
    try:
        ack = await self.query(stanza, timeout=25)
    except TimeoutError:
        raise DeliveryError('WhatsApp no confirmó el envío. Revisa la conexión del dispositivo vinculado.') from None
    if ack.tag not in ('ack','receipt'):
        raise DeliveryError('WhatsApp devolvió una confirmación de envío inesperada.')
    if ack.attrs.get('error') not in (None, '', '0', 0):
        code = str(ack.attrs['error'])
        safe_code = code if code.isdigit() else 'desconocido'
        raise DeliveryError(f'WhatsApp rechazó la respuesta (código {safe_code}).')


def install():
    Connection._relay_dm = relay_dm
