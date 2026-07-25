#!/usr/bin/env bash
#
# make-claude-zip.sh — package the Nectar repo for upload to Claude.
#
# Excludes: .git history, the generated .xcodeproj, binary/image assets,
# provisioning profiles/certs, and other build noise that isn't useful
# context for code review or debugging.
#
# Usage:
#   ./make-claude-zip.sh [source_dir] [output_zip]
#
# Defaults: source_dir=. (current directory), output_zip=nectar-claude.zip

set -euo pipefail

SRC="${1:-.}"
OUT="${2:-nectar-claude.zip}"

if [ ! -d "$SRC" ]; then
  echo "error: source dir '$SRC' does not exist" >&2
  exit 1
fi

# Resolve to an absolute path so the zip's internal paths are clean
# regardless of where this script is invoked from.
SRC="$(cd "$SRC" && pwd)"
OUT="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"

rm -f "$OUT"

cd "$SRC"

zip -r -q "$OUT" . \
  -x '.git/*' \
  -x '.git' \
  -x '*.xcodeproj/*' \
  -x '*.xcodeproj' \
  -x '__MACOSX/*' \
  -x '__MACOSX' \
  -x '*.DS_Store' \
  -x '*.png' \
  -x '*.jpg' \
  -x '*.jpeg' \
  -x '*.gif' \
  -x '*.webp' \
  -x '*.icns' \
  -x '*.pdf' \
  -x '*.mov' \
  -x '*.mp4' \
  -x '*.heic' \
  -x '*.xcassets/*' \
  -x '*.xcassets' \
  -x '*.cer' \
  -x '*.cer.enc' \
  -x '*.p12' \
  -x '*.p12.enc' \
  -x '*.mobileprovision' \
  -x '*.mobileprovision.enc' \
  -x '*.provisionprofile' \
  -x '*.provisionprofile.enc' \
  -x '*.xcuserstate' \
  -x '*.xcuserdatad/*' \
  -x '.build/*' \
  -x '.swiftpm/*' \
  -x '*/DerivedData/*' \
  -x 'appstore/screenshots/*' \
  -x '*.nnwtheme/*.css' \
  -x '*.nnwtheme/*.html'

echo "Wrote $OUT"
unzip -l "$OUT" | tail -1
