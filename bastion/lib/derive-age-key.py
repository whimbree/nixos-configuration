#!/usr/bin/env python3
"""Deterministically derive a per-MicroVM age key from the microvm key seed.

Reads the base64 seed on stdin and prints either the age identity
(AGE-SECRET-KEY-1...) or, with --pub, the matching recipient (age1...).

Derivation:  HKDF-SHA256(seed, info="sops-vm:<vmName>") -> 32 bytes -> X25519
private scalar -> Bech32-encoded age identity. The public key is computed by
age-keygen -y on the derived identity, so we never hand-roll the curve math.

Determinism guarantees the same vmName always yields the same key, so a lost
key image can be rebuilt identically (self-heal) from the one seed.
"""

import base64
import hashlib
import hmac
import subprocess
import sys
import tempfile

# Bech32 (BIP-0173, checksum constant 1 -- age uses bech32, not bech32m).
_CHARSET = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"


def _bech32_polymod(values):
    gen = [0x3B6A57B2, 0x26508E6D, 0x1EA119FA, 0x3D4233DD, 0x2A1462B3]
    chk = 1
    for v in values:
        top = chk >> 25
        chk = ((chk & 0x1FFFFFF) << 5) ^ v
        for i in range(5):
            chk ^= gen[i] if ((top >> i) & 1) else 0
    return chk


def _bech32_hrp_expand(hrp):
    return [ord(c) >> 5 for c in hrp] + [0] + [ord(c) & 31 for c in hrp]


def _bech32_create_checksum(hrp, data):
    values = _bech32_hrp_expand(hrp) + data
    polymod = _bech32_polymod(values + [0, 0, 0, 0, 0, 0]) ^ 1
    return [(polymod >> 5 * (5 - i)) & 31 for i in range(6)]


def _bech32_encode(hrp, data):
    combined = data + _bech32_create_checksum(hrp, data)
    return hrp + "1" + "".join(_CHARSET[d] for d in combined)


def _convertbits(data, frombits, tobits, pad=True):
    acc = 0
    bits = 0
    ret = []
    maxv = (1 << tobits) - 1
    for b in data:
        acc = (acc << frombits) | b
        bits += frombits
        while bits >= tobits:
            bits -= tobits
            ret.append((acc >> bits) & maxv)
    if pad and bits:
        ret.append((acc << (tobits - bits)) & maxv)
    return ret


def _hkdf_sha256(ikm, info, length=32):
    prk = hmac.new(b"\x00" * 32, ikm, hashlib.sha256).digest()  # extract
    okm = b""
    t = b""
    counter = 1
    while len(okm) < length:
        t = hmac.new(prk, t + info + bytes([counter]), hashlib.sha256).digest()
        okm += t
        counter += 1
    return okm[:length]


def derive_identity(seed, vm_name):
    key = _hkdf_sha256(seed, b"sops-vm:" + vm_name.encode(), 32)
    data = _convertbits(list(key), 8, 5)
    return _bech32_encode("age-secret-key-", data).upper()


def identity_to_recipient(identity):
    with tempfile.NamedTemporaryFile("w", suffix=".txt") as f:
        f.write(identity + "\n")
        f.flush()
        out = subprocess.run(
            ["age-keygen", "-y", f.name],
            check=True,
            capture_output=True,
            text=True,
        )
    return out.stdout.strip()


def main(argv):
    pub = "--pub" in argv
    args = [a for a in argv if not a.startswith("--")]
    if len(args) != 1:
        sys.stderr.write("usage: derive-age-key [--pub] <vmName>  (seed b64 on stdin)\n")
        return 2
    vm_name = args[0]
    seed_b64 = sys.stdin.read().strip()
    if not seed_b64:
        sys.stderr.write("error: empty seed on stdin\n")
        return 2
    seed = base64.b64decode(seed_b64)
    identity = derive_identity(seed, vm_name)
    print(identity_to_recipient(identity) if pub else identity)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
