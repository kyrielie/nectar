#!/bin/sh

set -e

case "${1:-}" in
  "")
    xcodebuild -project NetNewsWire.xcodeproj -scheme Nectar-iOS \
      -testPlan Nectar-CI \
      -xcconfig .github/ios-ci-no-signing.xcconfig \
      -destination 'platform=iOS Simulator,name=iPhone 17' \
      test
    ;;
  screenshots)
    xcodebuild -project NetNewsWire.xcodeproj -scheme Nectar-iOSUITests \
      -only-testing:Nectar-iOSUITests/NectarUITests/testTakeScreenshots \
      -xcconfig .github/ios-ci-no-signing.xcconfig \
      -destination 'platform=iOS Simulator,name=iPhone 17' \
      test
    ;;
  *)
    echo "Usage: $0 [screenshots]" >&2
    exit 2
    ;;
esac
