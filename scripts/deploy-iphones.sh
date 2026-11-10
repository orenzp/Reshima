#!/usr/bin/env bash
set -euo pipefail

# Wireless local installation helper for connected/paired iPhones (You & Wife)
# Requires full Xcode installed locally and iPhones paired over Wi-Fi.

cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "Error: xcodegen not found. Run 'make setup' first."
  exit 1
fi

echo "==> Generating Xcode project..."
(cd ios && xcodegen generate)

echo "==> Discovering connected/Wi-Fi iPhones..."
xcrun devicectl list devices

if [ -z "${APPLE_TEAM_ID:-}" ]; then
  echo "Note: Set APPLE_TEAM_ID=<your-personal-team-id> to sign with your free Apple ID."
  echo "You can find your Personal Team ID in Xcode -> Settings -> Accounts."
  exit 1
fi

echo "==> Building signed Debug app for connected device..."
xcodebuild build \
  -project ios/Reshima.xcodeproj \
  -scheme Reshima \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build/DerivedData \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  -allowProvisioningUpdates

APP_BUNDLE="build/DerivedData/Build/Products/Debug-iphoneos/Reshima.app"

if [ -n "${DEVICE_ID:-}" ]; then
  echo "==> Installing to device $DEVICE_ID..."
  xcrun devicectl device install app --device "$DEVICE_ID" "$APP_BUNDLE"
else
  echo "==> Build succeeded at $APP_BUNDLE"
  echo "Run: DEVICE_ID=<device-uuid-from-list> APPLE_TEAM_ID=$APPLE_TEAM_ID ./scripts/deploy-iphones.sh"
fi
