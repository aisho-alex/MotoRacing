#!/usr/bin/env bash
# Downloads the OFL-licensed ChakraPetch fonts for the HUD via the local proxy.
set -euo pipefail

BASE="https://raw.githubusercontent.com/google/fonts/main/ofl/chakrapetch"
DEST="$(cd "$(dirname "$0")/../.." && pwd)/assets/ui/fonts"
PROXY="--socks5-hostname 127.0.0.1:1080"

mkdir -p "$DEST"
for f in ChakraPetch-Bold.ttf ChakraPetch-SemiBold.ttf OFL.txt; do
  echo "fetch $f"
  curl -fsSL $PROXY "$BASE/$f" -o "$DEST/$f"
done

for f in ChakraPetch-Bold.ttf ChakraPetch-SemiBold.ttf; do
  sig=$(head -c 4 "$DEST/$f" | od -An -tx1 | tr -d ' \n')
  case "$sig" in
    00010000|74727565|4f54544f) echo "ok: $f ($sig)" ;;
    *) echo "FAIL: $f signature $sig"; exit 1 ;;
  esac
done
echo "fonts: ok"
