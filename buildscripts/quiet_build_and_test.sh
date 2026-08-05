#!/bin/bash
set -euo pipefail

# Same as build_and_test.sh, but quieter (xcbeautify --quiet, and Core Data/
# persistence log noise filtered from the test output).
# Note: depends on xcbeautify: <https://github.com/cpisciotta/xcbeautify>
# (brew install xcbeautify)

# === CONFIGURABLE VARIABLES ===
PROJECT_PATH="NetNewsWire.xcodeproj"
SCHEME_IOS="Nectar-iOS"
DESTINATION_IOS="platform=iOS Simulator,name=iPhone 17"

echo "🛠 Building iOS target..."
OS_ACTIVITY_MODE=disable xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME_IOS" \
  -destination "$DESTINATION_IOS" \
  clean build | xcbeautify --quiet

echo "✅ Build completed."

echo "🧪 Running tests for iOS target..."
OS_ACTIVITY_MODE=disable xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME_IOS" \
  -destination "$DESTINATION_IOS" \
  test 2>&1 | xcbeautify --quiet | sed '/CoreData/d;/persistence/d'

echo "🎉 Build and tests completed successfully."
