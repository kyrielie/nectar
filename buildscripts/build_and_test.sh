#!/bin/bash
set -euo pipefail

# This script builds the iOS target and runs its tests.
# Note: depends on xcbeautify: <https://github.com/cpisciotta/xcbeautify>
# (brew install xcbeautify)

# === CONFIGURABLE VARIABLES ===
PROJECT_PATH="NetNewsWire.xcodeproj"
SCHEME_IOS="Nectar-iOS"
DESTINATION_IOS="platform=iOS Simulator,name=iPhone 17"

echo "🛠 Building iOS target..."
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME_IOS" \
  -destination "$DESTINATION_IOS" \
  clean build | xcbeautify

echo "✅ Build completed."

echo "🧪 Running tests for iOS target..."
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME_IOS" \
  -destination "$DESTINATION_IOS" \
  test | xcbeautify

echo "🎉 Build and tests completed successfully."
