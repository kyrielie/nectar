#!/bin/sh

set -e

# The app-under-test seeds demo data additively (UITestDemoData.seedIfNeeded
# imports the OPML and never clears the account), and the account folder is
# loaded in AccountManager.init() before seeding runs. A container left over
# from an earlier run can therefore be stale or corrupt, which shows up as an
# empty timeline followed by a crash. Uninstalling the app wipes its container
# (accounts, databases, annotations) without resetting the whole simulator.
reset_app_container() {
  # Fails harmlessly if no simulator is booted or the app is not installed.
  xcrun simctl uninstall booted com.kyrielie.nectar >/dev/null 2>&1 || true
}

case "${1:-}" in
  "")
    xcodebuild -project NetNewsWire.xcodeproj -scheme Nectar-iOS \
      -testPlan Nectar-CI \
      -xcconfig .github/ios-ci-no-signing.xcconfig \
      -destination 'platform=iOS Simulator,name=iPhone 17' \
      test
    ;;
  screenshots)
    reset_app_container
    xcodebuild -project NetNewsWire.xcodeproj -scheme Nectar-iOSUITests \
      -only-testing:Nectar-iOSUITests/NectarUITests/testTakeScreenshots \
      -xcconfig .github/ios-ci-no-signing.xcconfig \
      -destination 'platform=iOS Simulator,name=iPhone 17' \
      test
    ;;
  screenshots-debug)
    # Same test, but with a fixed, freshly-cleared result bundle path and a
    # full log saved to disk. Afterwards:
    #   ./results.sh build/ui-test.xcresult
    #   grep '\[NectarUITest\]' build/ui-test.log
    reset_app_container
    mkdir -p build
    rm -rf build/ui-test.xcresult
    # No `pipefail` in POSIX sh, and `$?` after a pipe is tee's status, so
    # write the log via redirection and tail it instead of piping.
    set +e
    xcodebuild -project NetNewsWire.xcodeproj -scheme Nectar-iOSUITests \
      -only-testing:Nectar-iOSUITests/NectarUITests/testTakeScreenshots \
      -xcconfig .github/ios-ci-no-signing.xcconfig \
      -destination 'platform=iOS Simulator,name=iPhone 17' \
      -resultBundlePath build/ui-test.xcresult \
      test > build/ui-test.log 2>&1
    status=$?
    tail -n 40 build/ui-test.log
    echo
    echo "--- [NectarUITest] lines ---"
    grep '\[NectarUITest\]' build/ui-test.log
    exit "$status"
    ;;
  *)
    echo "Usage: $0 [screenshots|screenshots-debug]" >&2
    exit 2
    ;;
esac
