#!/usr/bin/env bash
#
# make-zip.sh -- package the Nectar repo for upload to Claude.
#
# Usage:
#   ./make-zip.sh                         default zip (no gallery-themes, no big fixtures)
#   ./make-zip.sh full                    everything: gallery-themes, crash logs, all fixtures
#   ./make-zip.sh themes                  every theme bundle from Themes/ and gallery-themes/
#   ./make-zip.sh themes NAME [NAME...]   only the named bundles (folder name without .nnwtheme)
#
# Options (any mode, before or after the mode):
#   -C DIR     source directory inside a git checkout (default: .)
#   -o FILE    output zip (default: nectar-claude.zip, or nectar-themes.zip in themes mode)
#   -h         show this help
#
# Examples:
#   ./make-zip.sh themes Beacon Nectar "OLED Black" Solarized
#   ./make-zip.sh themes -o picks.zip Upvote "Watch Later"
#   ./make-zip.sh full -o nectar-full.zip
#
# Old forms still work: `./make-zip.sh [source_dir] [output_zip]` and `FULL=1 ./make-zip.sh`.
# Theme names match case-insensitively against the bundle folder names, but accents must
# match the folder (for example "Wiener Werkstätte"). An unknown name stops the script
# and lists bundles whose names contain it.
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
# for code review or debugging. Unless full mode (or FULL=1) it also drops material
# that is large and rarely needed for a review session:
#   - scripts/MacCrashLogs/        (upstream sample crash logs, about 2.6 MB raw)
#   - gallery-themes/              (theme bundles; Themes/ keeps the bundled ones)
#   - package test fixtures        (Modules/*/Tests/*/Resources/*) of
#                                  MAX_FIXTURE_BYTES or more, which are mostly
#                                  large feed/HTML samples. Small fixtures stay so
#                                  the shape of the test inputs is still visible.
#
# Deliberately NOT excluded: .xcassets folders and .nnwtheme CSS/HTML. Asset
# catalogs are mostly Contents.json (colorset hex values, imageset file
# references, app icon slot config), small text files that are useful for
# reviewing color/theme code. The binary images inside them are still stripped
# by the extension-based excludes below.
#
# Environment: FULL=1 (same as full mode), MAX_FIXTURE_BYTES=60000.

set -euo pipefail

usage() { sed -n '3,/^$/p' "$0" | sed 's/^# \{0,1\}//' | sed '$d'; }

SRC="."
OUT=""
MODE="default"
FULL="${FULL:-0}"
MAX_FIXTURE_BYTES="${MAX_FIXTURE_BYTES:-30000}"
NAMES=()
POSITIONAL=()

# Mode keyword first, so a folder that differs from "themes" only by case
# (Themes/ on a case-insensitive volume) is never mistaken for it.
case "${1:-}" in
  full)   MODE="full"; FULL=1; shift ;;
  themes) MODE="themes"; shift ;;
esac

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    -C) [ "$#" -ge 2 ] || { echo "error: -C needs a directory" >&2; exit 1; }; SRC="$2"; shift 2 ;;
    -o) [ "$#" -ge 2 ] || { echo "error: -o needs a file" >&2; exit 1; }; OUT="$2"; shift 2 ;;
    -*) echo "error: unknown option '$1' (try -h)" >&2; exit 1 ;;
    *)  POSITIONAL+=("$1"); shift ;;
  esac
done

if [ "$MODE" = "themes" ]; then
  if [ "${#POSITIONAL[@]}" -gt 0 ]; then NAMES=("${POSITIONAL[@]}"); fi
else
  # Legacy form: [source_dir] [output_zip]
  if [ "${#POSITIONAL[@]}" -ge 1 ] && [ "$SRC" = "." ]; then SRC="${POSITIONAL[0]}"; fi
  if [ "${#POSITIONAL[@]}" -ge 2 ] && [ -z "$OUT" ]; then OUT="${POSITIONAL[1]}"; fi
  if [ "${#POSITIONAL[@]}" -ge 3 ]; then echo "error: too many arguments (try -h)" >&2; exit 1; fi
  if [ "$FULL" = "1" ]; then MODE="full"; fi
fi

if [ -z "$OUT" ]; then
  if [ "$MODE" = "themes" ]; then OUT="nectar-themes.zip"; else OUT="nectar-claude.zip"; fi
fi

if [ ! -d "$SRC" ]; then
  echo "error: source dir '$SRC' does not exist" >&2
  exit 1
fi

# Resolve to an absolute path so the zip's internal paths are clean
# regardless of where this script is invoked from.
SRC="$(cd "$SRC" && pwd)"
mkdir -p "$(dirname "$OUT")"
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

# Theme bundle folders under Themes/ and gallery-themes/, one path per line.
theme_bundle_dirs() {
  for root in Themes gallery-themes; do
    [ -d "$root" ] || continue
    for d in "$root"/*.nnwtheme; do
      [ -d "$d" ] && printf '%s\n' "$d"
    done
  done
}

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# Prints the bundle folders to include, one per line. With no names: all of them.
# With names: each must match a bundle stem case-insensitively, or the script stops.
select_theme_dirs() {
  all="$(theme_bundle_dirs)"
  if [ "${#NAMES[@]}" -eq 0 ]; then
    printf '%s\n' "$all"
    return
  fi
  missing=0
  for name in "${NAMES[@]}"; do
    want="$(lower "${name%.nnwtheme}")"
    found=0
    while IFS= read -r d; do
      [ -n "$d" ] || continue
      stem="$(basename "$d" .nnwtheme)"
      if [ "$(lower "$stem")" = "$want" ]; then
        printf '%s\n' "$d"
        found=1
      fi
    done <<EOF
$all
EOF
    if [ "$found" -eq 0 ]; then
      echo "error: no theme bundle named '$name'" >&2
      close="$(printf '%s\n' "$all" | while IFS= read -r d; do
        s="$(basename "$d" .nnwtheme)"
        case "$(lower "$s")" in *"$want"*) printf '  %s\n' "$s" ;; esac
      done)"
      if [ -n "$close" ]; then echo "  similar names:" >&2; printf '%s\n' "$close" >&2; fi
      missing=1
    fi
  done
  [ "$missing" -eq 0 ] || exit 1
}

# Keeps only files inside the selected bundle folders.
only_selected_themes() {
  sel="$1"
  while IFS= read -r f; do
    while IFS= read -r d; do
      [ -n "$d" ] || continue
      case "$f" in "$d"/*) printf '%s\n' "$f"; break ;; esac
    done <<EOF
$sel
EOF
  done
}

if [ "$MODE" = "themes" ]; then
  selected="$(select_theme_dirs | sort -u)"
  if [ -z "$selected" ]; then
    echo "error: no .nnwtheme bundles found under Themes/ or gallery-themes/" >&2
    exit 1
  fi
  existing_files | drop_noise | only_selected_themes "$selected" | zip -q "$OUT" -@
else
  existing_files | drop_noise | drop_bulk | zip -q "$OUT" -@
fi

echo "Wrote $OUT"
unzip -l "$OUT" | tail -1
