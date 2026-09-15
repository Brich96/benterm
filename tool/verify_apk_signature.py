"""Check which key signed an APK.

Android refuses to install a release over one signed with a different key,
so a release accidentally signed with the wrong key (a throwaway debug key,
say) installs once and then blocks every future update. CI runs this to fail
the build instead.

Usage:
    python tool/verify_apk_signature.py app.apk
    python tool/verify_apk_signature.py app.apk --expect <sha256>

The digest is the SHA-256 of the signer's SubjectPublicKeyInfo in DER form,
which matches:

    openssl pkcs12 -in key.p12 -nokeys -clcerts |
      openssl x509 -pubkey -noout |
      openssl pkey -pubin -outform DER |
      sha256sum
"""

import argparse
import hashlib
import struct
import sys

MAGIC = b'APK Sig Block 42'
SCHEME_IDS = {0x7109871A: 'v2', 0xF05368C0: 'v3'}


def _signing_block(data):
    """Returns the APK signing block's ID-value region, or None."""
    magic_at = data.rfind(MAGIC)
    if magic_at == -1:
        return None
    size_at = magic_at - 8
    (block_size,) = struct.unpack('<Q', data[size_at:size_at + 8])
    start = magic_at + len(MAGIC) - block_size - 8
    return data[start + 8:size_at]


def _pairs(block):
    offset = 0
    while offset + 12 <= len(block):
        (length,) = struct.unpack('<Q', block[offset:offset + 8])
        (pair_id,) = struct.unpack('<I', block[offset + 8:offset + 12])
        yield pair_id, block[offset + 12:offset + 8 + length]
        offset += 8 + length


def _chunk(buf, offset):
    """Reads one uint32 length-prefixed chunk; returns it and the next offset."""
    (length,) = struct.unpack('<I', buf[offset:offset + 4])
    return buf[offset + 4:offset + 4 + length], offset + 4 + length


def _public_keys(value):
    """Yields each signer's SubjectPublicKeyInfo from a v2/v3 block."""
    signers, _ = _chunk(value, 0)
    offset = 0
    while offset < len(signers):
        signer, offset = _chunk(signers, offset)
        inner = 0
        _, inner = _chunk(signer, inner)   # signed data
        _, inner = _chunk(signer, inner)   # signatures
        key, _ = _chunk(signer, inner)     # public key
        yield key


def signing_digests(path):
    """Returns {scheme: [sha256 of each signer's public key]} for an APK."""
    with open(path, 'rb') as handle:
        data = handle.read()

    block = _signing_block(data)
    if block is None:
        raise SystemExit(f'{path}: no APK signing block (unsigned?)')

    found = {}
    for pair_id, value in _pairs(block):
        scheme = SCHEME_IDS.get(pair_id)
        if scheme:
            found[scheme] = [
                hashlib.sha256(key).hexdigest() for key in _public_keys(value)
            ]
    if not found:
        raise SystemExit(f'{path}: signing block has no v2/v3 signature')
    return found


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk')
    parser.add_argument(
        '--expect',
        help='SHA-256 the signing key must match; exits non-zero otherwise',
    )
    args = parser.parse_args()

    digests = signing_digests(args.apk)
    for scheme, keys in sorted(digests.items()):
        for key in keys:
            print(f'{args.apk}  {scheme}  {key}')

    if args.expect:
        every = {key for keys in digests.values() for key in keys}
        if every != {args.expect.lower()}:
            print(
                f'\nExpected {args.expect.lower()}\n'
                f'but found {", ".join(sorted(every))}.\n'
                'A release signed with the wrong key cannot be installed over '
                'the previous one.',
                file=sys.stderr,
            )
            return 1
        print('\nSignature matches the expected release key.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
