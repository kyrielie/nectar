#!/usr/bin/env bash
#
# make-zip.sh -- package the Nectar repo for upload to Claude.
#
# The file list comes from git (`git ls-files --cached --others
# --exclude-standard`), so everything in .gitignore (examples/, testresults-out/,
# .claude/, testresults.txt, build output, ...) is left out automatically, and a
# new ignore rule shrinks the zip without editing this script. Untracked files
# that are not ignored are included, and so are uncommitted edits to tracked
# files, because the zip is built from the working tree, not from HEAD.
#
# On top of that it drops: the generated .xcodeproj, binary image/media files,
# provisioning profiles/certs, and other build noise that isn't useful context
# for code review or debugging. Unless FULL=1 it also drops material that is
# large and rarely needed for a review session:
#   - scripts/MacCrashLogs/        (upstream sample crash logs, about 2.6 MB raw)
#   - gallery-themes/              (151 theme bundles; Themes/ keeps the bundled ones)
#   - package test fixtures        (Modules/*/Tests/*/Resources/*) of
#                                  MAX_FIXTURE_BYTES or more, which are mostly
#                                  large feed/HTML samples. Small fixtures stay so
#                                  the shape of the test inputs is still visible.
# Measured on the tree this was written against: 5.46 MB -> about 2.2 MB zipped.
#
# Deliberately NOT excluded: .xcassets folders and .nnwtheme CSS/HTML.
# Asset catalogs are mostly Contents.json (colorset hex values, imageset
# file references, app icon slot config) -- small text files that are
# genuinely useful for reviewing color/theme code, not build noise. The
# actual binary images inside them (imageset PNGs, etc.) are still
# stripped by the extension-based excludes below, so this doesn't bloat
# the archive -- it just stops silently deleting the metadata that
# describes what those images are. Previously this dropped the entire
# .xcassets tree, which meant no AI session working from this
# zip could ever see what accent/theme colors or icon slots existed --
# confirmed as an active blind spot in iOS/MainTimeline/Cell/BadgeColorTable.swift's
# header comment before that fix.
#
# Usage:
#   ./make-zip.sh [source_dir] [output_zip]
#   FULL=1 ./make-zip.sh                 # keep crash logs, gallery themes, all fixtures
#   MAX_FIXTURE_BYTES=60000 ./make-zip.sh
#
# source_dir must be inside a git checkout.
# Defaults: source_dir=. (current directory), output_zip=nectar-claude.zip

set -euo pipefail

SRC="${1:-.}"
OUT="${2:-nectar-claude.zip}"
FULL="${FULL:-0}"
MAX_FIXTURE_BYTES="${MAX_FIXTURE_BYTES:-30000}"

if [ ! -d "$SRC" ]; then
  echo "error: source dir '$SRC' does not exist" >&2
  exit 1
fi

# Resolve to an absolute path so the zip's internal paths are clean
# regardless of where this script is invoked from.
SRC="$(cd "$SRC" && pwd)"
OUT="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"

if ! git -C "$SRC" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "error: '$SRC' is not inside a git work tree" >&2
  exit 1
fi

rm -f "$OUT"

# Tracked plus untracked-but-not-ignored paths, relative to the repo root.
# Run from the top level so a source_dir that is a subdirectory still works.
cd "$(git -C "$SRC" rev-parse --show-toplevel)"

# Tracked files that were deleted in the working tree are still listed by
# `ls-files --cached`; skip anything that is not a file on disk.
existing_files() {
  git -c core.quotepath=off ls-files --cached --others --exclude-standard | sort -u |
    while IFS= read -r f; do
      if [ -f "$f" ]; then printf '%s\n' "$f"; fi
    done
}

# Always applied (same coverage as the old zip -x list).
drop_noise() {
  grep -Ev \
    -e '\.(png|jpe?g|gif|webp|icns|pdf|mov|mp4|heic|cer|p12|mobileprovision|provisionprofile|xcuserstate)(\.enc)?$' \
    -e '(^|/)(\.DS_Store|__MACOSX|\.build|\.swiftpm|DerivedData)(/|$)' \
    -e '\.xcodeproj(/|$)' \
    -e '\.xcuserdatad/' \
    -e '^appstore/screenshots/' || true
}

# Skipped when FULL=1.
drop_bulk() {
  if [ "$FULL" = "1" ]; then
    cat
    return
  fi
  grep -Ev -e '^(scripts/MacCrashLogs|gallery-themes)/' |
    while IFS= read -r f; do
      case "$f" in
        Modules/*/Tests/*/Resources/*)
          size="$(wc -c < "$f" | tr -d ' ')"
          if [ "$size" -ge "$MAX_FIXTURE_BYTES" ]; then continue; fi
          ;;
      esac
      printf '%s\n' "$f"
    done
}

existing_files | drop_noise | drop_bulk | zip -q "$OUT" -@

echo "Wrote $OUT"
unzip -l "$OUT" | tail -1
