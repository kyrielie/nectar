#!/bin/bash
# Regenerates iOS/Resources/ThemeColorTable.json by running
# ThemeColorTableGeneratorTests on an iOS simulator, then checks the result with
# ThemeColorTableGuardTests. Needs macOS with Xcode (the probe hosts a WKWebView).
# Run it after editing core.css, a bundled theme's stylesheet.css or template.html,
# Shared/Article Rendering/template.html, or ArticleThemeColorProbe's logic.
# See docs/theme-testing.md.
#
#   scripts/regenerate-theme-colors.sh            regenerate, then verify
#   scripts/regenerate-theme-colors.sh --no-verify
set -euo pipefail
cd "$(dirname "$0")/.."

verify=1
[ "${1:-}" = "--no-verify" ] && verify=0

destination="${DESTINATION:-platform=iOS Simulator,name=iPhone 17}"
table="iOS/Resources/ThemeColorTable.json"

# The Debug xcconfig adds -warn-long-function-bodies=650 and warnings are errors, so a busy
# machine turns a slow type-check into a build failure. Demote warnings for this run only.
# Do not override OTHER_SWIFT_FLAGS here: a command-line value replaces the flags that Swift
# package targets get from their own swiftSettings (Account's InferIsolatedConformances, for
# example) and breaks their build.

run_tests() {
  xcodebuild \
    -project NetNewsWire.xcodeproj \
    -scheme Nectar-iOS \
    -xcconfig .github/ios-ci-no-signing.xcconfig \
    -destination "$destination" \
    -enableCodeCoverage NO \
    "$@" \
    SWIFT_TREAT_WARNINGS_AS_ERRORS=NO \
    test
}

xcodegen generate

TEST_RUNNER_REGENERATE_THEME_COLOR_TABLE=1 \
  run_tests -only-testing:Nectar-iOSTests/ThemeColorTableGeneratorTests

if [ ! -f "$table" ]; then
  echo "error: $table was not written" >&2
  exit 1
fi

# A new file under iOS/ is only bundled after the project is generated again.
xcodegen generate

if [ "$verify" -eq 1 ]; then
  run_tests -only-testing:Nectar-iOSTests/ThemeColorTableGuardTests
fi

git status --short -- "$table"
echo "Done. Review and commit $table."
