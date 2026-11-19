"""Regression coverage using independent libsodium Ed25519 signatures."""
import hashlib
import unittest

from nacl.bindings import crypto_sign_ed25519_pk_to_curve25519
from nacl.signing import SigningKey

from signal_compat import verify_signal_signature, install
from piwapp.crypto import signal_curve


class SignalSignatureTests(unittest.TestCase):
    def test_both_public_key_sign_bits_and_tampering(self):
        install()
        sign_bits = set()
        message = b'Fideli pairing signature regression'
        for index in range(64):
            key = SigningKey(hashlib.sha256(str(index).encode()).digest())
            public = bytes(key.verify_key)
            curve_public = crypto_sign_ed25519_pk_to_curve25519(public)
            signature = bytearray(key.sign(message).signature)
            sign_bit = public[31] & 0x80
            sign_bits.add(sign_bit)
            signature[63] |= sign_bit
            signature = bytes(signature)
            with self.subTest(index=index):
                self.assertTrue(verify_signal_signature(curve_public, message, signature))
                self.assertTrue(signal_curve.verify_signature(b'\x05' + curve_public, message, signature))
                self.assertFalse(signal_curve.verify_signature(b'\x05' + curve_public, message + b'changed', signature))
                self.assertFalse(verify_signal_signature(curve_public, message + b'changed', signature))
        self.assertEqual(sign_bits, {0, 0x80})

    def test_invalid_lengths(self):
        self.assertFalse(verify_signal_signature(b'', b'message', b''))


if __name__ == '__main__':
    unittest.main()
