xcodebuild -project NetNewsWire.xcodeproj -scheme Nectar-iOS \
  -testPlan Nectar-CI \
  -xcconfig .github/ios-ci-no-signing.xcconfig \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  test
