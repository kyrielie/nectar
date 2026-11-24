#!/usr/bin/env bash
# ==============================================================================
# test.sh — Run Nectar's test suite and SwiftLint locally
#
# Mirrors the local testing workflow used across the suite (same as Ambrosia).
#
# Usage:
#   ./test.sh                     Run SwiftLint + full unit test suite (Nectar-CI)
#   ./test.sh --no-lint           Skip SwiftLint, run unit tests only
#   ./test.sh --lint-only         Run SwiftLint only, skip tests
#   ./test.sh --filter PATTERN    Run only tests matching PATTERN
#                                  (e.g. AO3KitTests/AO3LinkTests)
#   ./test.sh -q | --quiet        Suppress verbose output; print pass/fail summary
#   ./test.sh performance         Run XCTest measure tests (Nectar-Performance plan)
#   ./test.sh screenshots         Run screenshot UI tests (resets app container first)
#   ./test.sh screenshots-debug   Run screenshot UI tests with full log and result bundle
#   ./test.sh -h | --help         Show this message
# ==============================================================================

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

PROJECT="NetNewsWire.xcodeproj"
SCHEME="Nectar-iOS"
DESTINATION="platform=iOS Simulator,name=iPhone 17"
XCCONFIG=".github/ios-ci-no-signing.xcconfig"
TEST_PLAN="Nectar-CI"

RUN_LINT=1
RUN_TESTS=1
QUIET=0
FILTER=""
MODE="ci"

# Reset app container for UI tests
reset_app_container() {
  xcrun simctl uninstall booted com.kyrielie.nectar >/dev/null 2>&1 || true
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-lint)
      RUN_LINT=0
      shift
      ;;
    --lint-only)
      RUN_TESTS=0
      shift
      ;;
    --filter)
      FILTER="${2:?--filter requires a PATTERN argument}"
      shift 2
      ;;
    -q|--quiet)
      QUIET=1
      shift
      ;;
    performance)
      MODE="performance"
      TEST_PLAN="Nectar-Performance"
      shift
      ;;
    screenshots)
      MODE="screenshots"
      RUN_LINT=0
      shift
      ;;
    screenshots-debug)
      MODE="screenshots-debug"
      RUN_LINT=0
      shift
      ;;
    -h|--help)
      sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Run './test.sh --help' for usage." >&2
      exit 1
      ;;
  esac
done

status=0

# Step 1: SwiftLint
if [[ "$RUN_LINT" -eq 1 ]]; then
  if command -v swiftlint >/dev/null 2>&1; then
    echo "==> Running SwiftLint (swiftlint lint --strict)"
    if ! swiftlint lint --strict; then
      echo "==> SwiftLint failed" >&2
      status=1
    else
      echo "==> SwiftLint passed"
    fi
  else
    echo "==> SwiftLint not installed, skipping (install with: brew install swiftlint)" >&2
  fi
fi

if [[ "$status" -ne 0 ]]; then
  echo "==> Lint failed. Aborting tests." >&2
  exit "$status"
fi

# Step 2: Tests
if [[ "$RUN_TESTS" -eq 1 ]]; then
  if [[ "$MODE" == "screenshots" ]]; then
    echo "==> Running screenshot UI tests (resetting container first)..."
    reset_app_container
    xcodebuild_args=(
      -project "$PROJECT"
      -scheme "Nectar-iOSUITests"
      -only-testing:Nectar-iOSUITests/NectarUITests/testTakeScreenshots
      -xcconfig "$XCCONFIG"
      -destination "$DESTINATION"
      test
    )
  elif [[ "$MODE" == "screenshots-debug" ]]; then
    echo "==> Running screenshot UI tests with debug log..."
    reset_app_container
    mkdir -p build
    rm -rf build/ui-test.xcresult
    set +e
    xcodebuild -project "$PROJECT" \
      -scheme "Nectar-iOSUITests" \
      -only-testing:Nectar-iOSUITests/NectarUITests/testTakeScreenshots \
      -xcconfig "$XCCONFIG" \
      -destination "$DESTINATION" \
      -resultBundlePath build/ui-test.xcresult \
      test > build/ui-test.log 2>&1
    test_status=$?
    tail -n 40 build/ui-test.log
    echo
    echo "--- [NectarUITest] lines ---"
    grep '\[NectarUITest\]' build/ui-test.log || true
    exit "$test_status"
  else
    echo "==> Running tests ($TEST_PLAN on $DESTINATION)..."
    xcodebuild_args=(
      -project "$PROJECT"
      -scheme "$SCHEME"
      -testPlan "$TEST_PLAN"
      -xcconfig "$XCCONFIG"
      -destination "$DESTINATION"
      test
    )
    if [[ -n "$FILTER" ]]; then
      xcodebuild_args=(-only-testing:"$FILTER" "${xcodebuild_args[@]}")
    fi
  fi

  set +e
  if [[ "$QUIET" -eq 1 ]]; then
    xcodebuild "${xcodebuild_args[@]}" >/tmp/nectar-test-output.log 2>&1
    test_status=$?
  elif command -v xcbeautify >/dev/null 2>&1; then
    xcodebuild "${xcodebuild_args[@]}" 2>&1 | xcbeautify
    test_status=${PIPESTATUS[0]}
  else
    xcodebuild "${xcodebuild_args[@]}"
    test_status=$?
  fi
  set -e

  if [[ "$test_status" -ne 0 ]]; then
    status=1
    echo "==> Tests failed (exit $test_status)" >&2
    if [[ "$QUIET" -eq 1 ]]; then
      echo "    Full output: /tmp/nectar-test-output.log" >&2
    fi
  else
    echo "==> Tests passed"
  fi
fi

if [[ "$status" -eq 0 ]]; then
  echo "==> All checks passed"
else
  echo "==> One or more checks failed" >&2
fi

exit "$status"
