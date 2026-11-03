#!/bin/zsh
#
# Build a Release DeepSwift.app, embed the pinned isolated runtime, and produce
# a distributable zip. Signing and notarization credentials stay in the
# caller's environment; this script never stores them.
#
# Required for a Developer ID build:
#   DEEPSWIFT_CODESIGN_IDENTITY="Developer ID Application: ..."
# Optional:
#   DEEPSWIFT_NODE_BIN=/absolute/path/to/node
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${DEEPSWIFT_BUILD_DIR:-$ROOT/.local/build}"
DERIVED="$BUILD_DIR/DerivedData"
APP="$DERIVED/Build/Products/Release/DeepSwift.app"
IDENTITY="${DEEPSWIFT_CODESIGN_IDENTITY:--}"

mkdir -p "$BUILD_DIR"
xcodebuild \
  -project "$ROOT/DeepSwift.xcodeproj" \
  -scheme DeepSwift \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_IDENTITY="$IDENTITY" \
  DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-YM5G2M8PV9}" \
  build

DEEPSWIFT_CODESIGN_IDENTITY="$IDENTITY" "$ROOT/Scripts/package-runtime.sh" "$APP"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
ZIP="$BUILD_DIR/DeepSwift-${VERSION}.zip"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "Release app: $APP"
echo "Distribution zip: $ZIP"
if [[ "$IDENTITY" == "-" ]]; then
  echo "AD-HOC SIGNED: local testing only. Re-run with a Developer ID identity for distribution." >&2
else
  echo "Signed with: $IDENTITY"
  echo "Next: Scripts/notarize.sh \"$ZIP\"" >&2
fi
