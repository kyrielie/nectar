#!/usr/bin/env bash
#
# make-claude-zip.sh — package the Nectar repo for upload to Claude.
#
# Excludes: .git history, the generated .xcodeproj, binary image files,
# provisioning profiles/certs, and other build noise that isn't useful
# context for code review or debugging.
#
# Deliberately NOT excluded: .xcassets folders and .nnwtheme CSS/HTML.
# Asset catalogs are mostly Contents.json (colorset hex values, imageset
# file references, app icon slot config) -- small text files that are
# genuinely useful for reviewing color/theme code, not build noise. The
# actual binary images inside them (imageset PNGs, etc.) are still
# stripped by the extension-based excludes below, so this doesn't bloat
# the archive -- it just stops silently deleting the metadata that
# describes what those images are. Previously this dropped the entire
# .xcassets tree (see the exclusions below this comment in prior
# versions of this script), which meant no AI session working from this
# zip could ever see what accent/theme colors or icon slots existed --
# confirmed as an active blind spot in iOS/MainTimeline/Cell/BadgeColorTable.swift's
# header comment before this fix.
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
  -x 'appstore/screenshots/*'

echo "Wrote $OUT"
unzip -l "$OUT" | tail -1
