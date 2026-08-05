from __future__ import annotations

import base64
import string
import sys
from pathlib import Path

if len(sys.argv) != 3:
    raise SystemExit("usage: decode_truncated_base64.py INPUT OUTPUT")

source = Path(sys.argv[1])
destination = Path(sys.argv[2])
allowed = frozenset(string.ascii_letters + string.digits + "+/=")
payload = "".join(character for character in source.read_text(encoding="utf-8") if character in allowed)
payload = payload.rstrip("=")

if not payload:
    raise SystemExit(f"empty payload: {source}")

# A Base64 stream cannot contain a single data character in its last quartet.
# The repository payload was cut at its end, so discard only that incomplete
# final character and preserve every complete decoded byte before it.
if len(payload) % 4 == 1:
    payload = payload[:-1]

raw = base64.b64decode(payload + "=" * (-len(payload) % 4), validate=False)
destination.write_bytes(raw)
print(f"decoded {len(raw)} bytes to {destination}")
