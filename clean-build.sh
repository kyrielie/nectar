#!/usr/bin/env bash
#
# clean-build.sh — remove SwiftPM/Xcode build output for this repo.
#
# Safe to run any time: everything this deletes is gitignored derived
# output (.build/, build/, DerivedData/) and gets regenerated on the next
# build. It does NOT touch Package.resolved or any source files.
#
# Usage:
#   ./clean-build.sh              # clean .build/build/DerivedData under the repo
#   ./clean-build.sh --dry-run    # show what would be removed, delete nothing
#   ./clean-build.sh --spm-cache  # also clear ~/Library/Caches/org.swift.swiftpm
#
set -euo pipefail

DRY_RUN=false
CLEAN_SPM_CACHE=false

for arg in "$@"; do
	case "$arg" in
		--dry-run) DRY_RUN=true ;;
		--spm-cache) CLEAN_SPM_CACHE=true ;;
		-h|--help)
			grep '^#' "$0" | sed 's/^#//'
			exit 0
			;;
		*)
			echo "Unknown option: $arg" >&2
			exit 1
			;;
	esac
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

human_size() {
	# $1 = path. Prints a human-readable size, or "0B" if missing.
	if [[ -e "$1" ]]; then
		du -sh "$1" 2>/dev/null | cut -f1
	else
		echo "0B"
	fi
}

remove() {
	local path="$1"
	[[ -e "$path" ]] || return 0
	local size
	size="$(human_size "$path")"
	if $DRY_RUN; then
		echo "would remove ($size): $path"
	else
		echo "removing ($size): $path"
		trash "$path"
	fi
}

echo "Repo root: $REPO_ROOT"
echo

# Every package's own .build/ (Modules/*/.build), plus any top-level
# .build/ or build/ directory anywhere in the repo (skips anything already
# inside node_modules, just in case).
while IFS= read -r -d '' dir; do
	remove "$dir"
done < <(find "$REPO_ROOT" \( -name ".build" -o -name "build" \) -type d -not -path '*/node_modules/*' -print0)

# Xcode DerivedData entries for this project. XcodeGen regenerates a new
# .xcodeproj each time, so stale DerivedData for old project UUIDs can
# accumulate here and is often the biggest single offender.
DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData"
if [[ -d "$DERIVED_DATA" ]]; then
	while IFS= read -r -d '' dir; do
		remove "$dir"
	done < <(find "$DERIVED_DATA" -maxdepth 1 -iname "Nectar-iOS-*" -type d -print0)
fi

if $CLEAN_SPM_CACHE; then
	remove "$HOME/Library/Caches/org.swift.swiftpm"
fi

echo
if $DRY_RUN; then
	echo "Dry run only — nothing was deleted. Re-run without --dry-run to clean."
else
	echo "Done. Next build will re-resolve dependencies and recompile from scratch."
fi
