#!/bin/zsh
#
# cleanup-ios-only.sh
#
# Strips a NetNewsWire fork down to iOS-only. Deletes Mac app source,
# Mac-only extensions' resources, and unreferenced duplicate/Mac-release
# folders. Uses `trash` instead of `rm` so everything is recoverable from
# the Trash if something looks wrong afterward.
#
# Run from the root of your cloned repo (the folder containing
# NetNewsWire.xcodeproj). After running this, open the project in Xcode
# and remove the Mac-only TARGETS by hand (see printed instructions at the
# end) — that part can't be done safely by editing project.pbxproj text.
#
# Requires `trash` (macOS): brew install trash

set -euo pipefail

if ! command -v trash >/dev/null 2>&1; then
  echo "error: 'trash' not found. Install it with: brew install trash" >&2
  exit 1
fi

if [[ ! -e "NetNewsWire.xcodeproj" ]]; then
  echo "error: NetNewsWire.xcodeproj not found in $(pwd)." >&2
  echo "cd into the repo root (the folder containing NetNewsWire.xcodeproj) and re-run." >&2
  exit 1
fi

echo "Working in: $(pwd)"
echo

# --- Confirmed-safe deletions -------------------------------------------
# Folders: whole units, verified either unreferenced by project.pbxproj or
# (Mac/) a standalone PBXFileSystemSynchronizedRootGroup that only the Mac
# targets pull from.
folders_to_trash=(
  "Mac"
  "AppleScript"
  "Appcasts"
  "AppStore"
  "Resources"   # root-level dir; verified byte-identical duplicate of
                # Shared/Resources/Themes and unreferenced by the project
)

# Individual files: xcconfigs for targets you're about to delete in Xcode,
# plus the Mac-only CI signing config.
files_to_trash=(
  "xcconfig/NetNewsWire_macapp_target.xcconfig"
  "xcconfig/NetNewsWire_shareextension_target.xcconfig"
  "xcconfig/NetNewsWire_safariextension_target.xcconfig"
  "xcconfig/NetNewsWireTests_target.xcconfig"
  ".github/macos-ci-no-signing.xcconfig"
)

echo "--- Folders to trash ---"
for f in "${folders_to_trash[@]}"; do
  if [[ -e "$f" ]]; then
    echo "  trashing: $f"
    trash "$f"
  else
    echo "  skip (not found): $f"
  fi
done

echo
echo "--- Files to trash ---"
for f in "${files_to_trash[@]}"; do
  if [[ -e "$f" ]]; then
    echo "  trashing: $f"
    trash "$f"
  else
    echo "  skip (not found): $f"
  fi
done

echo
echo "Done with on-disk cleanup."
echo
echo "=========================================================================="
echo "MANUAL STEPS STILL NEEDED IN XCODE (do these before committing):"
echo "=========================================================================="
echo "1. Open NetNewsWire.xcodeproj, select the project in the navigator, and"
echo "   under TARGETS, delete (minus button):"
echo "     - NetNewsWire            (Mac app)"
echo "     - NetNewsWireTests       (Mac unit tests)"
echo "     - NetNewsWire Share Extension   (Mac share extension)"
echo "     - Subscribe to Feed      (Mac Safari extension)"
echo
echo "2. In Project > Package Dependencies, remove the Sparkle package — it"
echo "   was only used by Mac/AppDelegate.swift, which is now gone."
echo
echo "3. In the scheme manager (Product > Scheme > Manage Schemes), delete"
echo "   any leftover schemes for the targets removed above."
echo
echo "4. Build the NetNewsWire-iOS scheme to confirm nothing broke."
echo "=========================================================================="
echo
echo "Left for you to decide (not touched by this script):"
echo "  - Tests/NetNewsWireTests/   (Mac unit tests; some cover Shared/Modules"
echo "    logic worth porting into Tests/NetNewsWire-iOSTests/ instead of losing)"
echo "  - Technotes/                (docs, no build impact either way)"
echo "  - .github/workflows/ci.yml  (has a macos-tests job to remove, plus"
echo "    swiftlint/ios-simulator-tests jobs to keep)"
echo "  - buildscripts/certs, buildscripts/old_buildnnw, buildscripts/profile"
echo "    (look Mac-signing-specific but not yet verified file-by-file)"
