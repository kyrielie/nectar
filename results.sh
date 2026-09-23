#!/bin/sh
# Usage: ./results.sh <path-to.xcresult> [output-dir]
#
# Extracts everything useful from a test result bundle:
#   summary.json       overall pass/fail and failure text (same as before)
#   details.json       per-test detail including failure locations
#   attachments/       screenshots and accessibility-hierarchy dumps that
#                      NectarUITests attaches (before-back-tap, etc.)
#
# Only `get test-results summary` is exercised elsewhere in this repo
# (ci.yml). `get test-results details` and `export attachments` are newer
# xcresulttool subcommands; if your Xcode's flags differ, run
#   xcrun xcresulttool get test-results --help
#   xcrun xcresulttool export attachments --help
# Each step below is allowed to fail without stopping the others.

set -u

if [ $# -lt 1 ]; then
  echo "Usage: $0 <path-to.xcresult> [output-dir]" >&2
  exit 2
fi

result="$1"
out="${2:-testresults-out}"
mkdir -p "$out"

echo "==> summary"
xcrun xcresulttool get test-results summary --path "$result" > "$out/summary.json" \
  || echo "    summary failed"
# Keep the old behaviour: results.sh used to write testresults.txt.
cp "$out/summary.json" testresults.txt 2>/dev/null

echo "==> details"
xcrun xcresulttool get test-results details --path "$result" > "$out/details.json" \
  || echo "    details failed (see: xcrun xcresulttool get test-results --help)"

echo "==> attachments"
xcrun xcresulttool export attachments --path "$result" --output-path "$out/attachments" \
  || echo "    export failed (see: xcrun xcresulttool export attachments --help)"

echo "==> done: $out"
ls "$out" "$out/attachments" 2>/dev/null
