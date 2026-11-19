"""Signal Curve25519 signature compatibility for PiWapp 0.1.1.

Signal stores the Edwards public-key sign bit in signature byte 63. PiWapp's
verifier assumes that bit is always zero and rejects valid flagged signatures.
Keep full Ed25519 signature verification after restoring the public-key sign.
"""
from nacl.exceptions import BadSignatureError
from nacl.signing import VerifyKey


def verify_signal_signature(public_key: bytes, message: bytes, signature: bytes) -> bool:
    if len(public_key) != 32 or len(signature) != 64:
        return False
    prime = 2**255 - 19
    u = int.from_bytes(public_key, 'little') & (2**255 - 1)
    if (u + 1) % prime == 0:
        return False
    y = (u - 1) * pow(u + 1, prime - 2, prime) % prime
    ed_public = bytearray(y.to_bytes(32, 'little'))
    ed_public[31] |= signature[63] & 0x80
    clean_signature = bytearray(signature)
    clean_signature[63] &= 0x7f
    try:
        VerifyKey(bytes(ed_public)).verify(message, bytes(clean_signature))
        return True
    except (BadSignatureError, ValueError):
        return False


def install() -> None:
    from piwapp import crypto
    from piwapp.crypto import key_utils
    from piwapp.socket import connection
    # Signal's pre-key/session path calls key_utils through signal_curve; patch
    # that path as well as the login path, preserving signature verification.
    key_utils.xeddsa_verify = verify_signal_signature
    crypto.xeddsa_verify = verify_signal_signature
    connection.xeddsa_verify = verify_signal_signature
