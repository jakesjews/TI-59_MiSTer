#!/usr/bin/env python3
"""Verify every framework path against the pinned upstream template manifest."""
import hashlib
from pathlib import Path

root = Path(__file__).resolve().parents[1]
expected = {}
for line in (root / 'docs/framework.sha256').read_text().splitlines():
    digest, name = line.split('  ', 1)
    expected[name] = digest
actual = {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
          for p in (root / 'sys').rglob('*') if p.is_file()}
bad = sorted(k for k in expected.keys() | actual.keys() if expected.get(k) != actual.get(k))
if bad:
    raise SystemExit('Framework mismatch: ' + ', '.join(bad))
print(f'PASS: all {len(actual)} sys files match Template_MiSTer 5dda37366d02b04b8448da7b322235c1831af811')
