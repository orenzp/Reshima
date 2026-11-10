#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:-build/DerivedData/Build/Products/Release-iphoneos/Reshima.app}"
IPA_OUTPUT="${2:-build/Reshima.ipa}"

if [ ! -d "$APP_PATH" ]; then
  echo "Error: .app bundle not found at $APP_PATH"
  exit 1
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

mkdir -p "$WORK_DIR/Payload"
cp -R "$APP_PATH" "$WORK_DIR/Payload/Reshima.app"

mkdir -p "$(dirname "$IPA_OUTPUT")"
IPA_ABS="$(cd "$(dirname "$IPA_OUTPUT")" && pwd)/$(basename "$IPA_OUTPUT")"

(
  cd "$WORK_DIR"
  zip -qry "$IPA_ABS" Payload
)

echo "==> Packaged IPA at: $IPA_ABS ($(du -h "$IPA_ABS" | cut -f1))"
