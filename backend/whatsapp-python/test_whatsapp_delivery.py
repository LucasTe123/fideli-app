import unittest
from types import SimpleNamespace
from unittest.mock import AsyncMock, patch
from piwapp.binary import BinaryNode
from whatsapp_delivery import relay_dm, participant_nodes, DeliveryError


def devices_response(include_recipient=True):
    users = []
    for user in ['own'] + (['other'] if include_recipient else []):
        users.append(BinaryNode(tag='user', attrs={'jid':user+'@s.whatsapp.net'}, content=[
            BinaryNode(tag='devices', content=[BinaryNode(tag='device-list', content=[BinaryNode(tag='device', attrs={'id':'0'})])])]))
    return BinaryNode(tag='iq', content=[BinaryNode(tag='usync', content=[BinaryNode(tag='list', content=users)])])


class DeliveryTests(unittest.IsolatedAsyncioTestCase):
    async def test_missing_recipient_is_not_reported_as_sent(self):
        client = SimpleNamespace(creds=SimpleNamespace(me=SimpleNamespace(id='own:5@s.whatsapp.net',lid=None)), query=AsyncMock(return_value=devices_response(False)))
        with self.assertRaises(DeliveryError): await relay_dm(client,'other@s.whatsapp.net',object(),'id')
        self.assertEqual(client.query.await_count,1)

    async def test_relay_requires_ack_and_rejects_server_errors(self):
        for error in (None,'403'):
            attrs = {'class':'message'}
            if error: attrs['error']=error
            query = AsyncMock(side_effect=[devices_response(),BinaryNode(tag='ack',attrs=attrs)])
            client = SimpleNamespace(creds=SimpleNamespace(me=SimpleNamespace(id='own:5@s.whatsapp.net',lid=None)), query=query, signal_store=SimpleNamespace(contains_session=lambda _:True))
            with patch('whatsapp_delivery.participant_nodes',return_value=([BinaryNode(tag='to')],False)), patch('whatsapp_delivery.ms.dsm_message',return_value=object()):
                if error:
                    with self.assertRaises(DeliveryError): await relay_dm(client,'other@s.whatsapp.net',object(),'id')
                else: await relay_dm(client,'other@s.whatsapp.net',object(),'id')
            self.assertEqual(query.await_args.kwargs['timeout'],25)
            self.assertEqual(query.await_args.args[0].tag,'message')

    def test_encryption_failures_are_not_silently_skipped(self):
        with patch('whatsapp_delivery.encode_wa_message',return_value=b'message'), patch('whatsapp_delivery.SessionCipher') as cipher:
            cipher.return_value.encrypt.side_effect=ValueError('bad session')
            with self.assertRaises(DeliveryError): participant_nodes(object(),object(),['other@s.whatsapp.net'])
