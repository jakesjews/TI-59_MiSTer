#!/usr/bin/env bash
# The oracle stays outside the synthesizable project and is ignored by Git.
set -euo pipefail
cd "$(dirname "$0")/.."
target=research/sources/Calc-U-59
revision=e6325e955dff61aa51b596317436fae34249cb0c
if [ ! -d "$target/.git" ]; then
  git clone https://github.com/tinue/Calc-U-59.git "$target"
  git -C "$target" checkout --detach "$revision"
fi
if [ "$(git -C "$target" rev-parse HEAD)" != "$revision" ]; then
  echo "Oracle must be at $revision; preserving the existing checkout." >&2
  echo "Use git -C $target checkout $revision after checking its local changes." >&2
  exit 1
fi
echo "Oracle ready at $revision (PolyForm Noncommercial 1.0.0; local testing only)."
