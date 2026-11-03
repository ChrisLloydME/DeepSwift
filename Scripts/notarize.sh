#!/bin/zsh
#
# Submit a signed zip to Apple's notary service and staple the result.
# Credentials are read from the environment and are never written to the app,
# the repository, or shell history.
#
# Required:
#   APPLE_ID, APPLE_TEAM_ID, APPLE_APP_PASSWORD (app-specific password)
# Usage: Scripts/notarize.sh <DeepSwift.zip>
#
set -euo pipefail
ZIP="${1:?usage: notarize.sh <DeepSwift.zip>}"
: "${APPLE_ID:?set APPLE_ID}"
: "${APPLE_TEAM_ID:?set APPLE_TEAM_ID}"
: "${APPLE_APP_PASSWORD:?set APPLE_APP_PASSWORD}"

xcrun notarytool submit "$ZIP" \
  --apple-id "$APPLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --password "$APPLE_APP_PASSWORD" \
  --wait

# The zip is not itself stapleable; staple the app and recreate the final
# distribution archive so the exported zip carries the ticket.
APP_DIR="$(dirname "$ZIP")/DeepSwift.app"
if [[ -d "$APP_DIR" ]]; then
  xcrun stapler staple "$APP_DIR"
  xcrun stapler validate "$APP_DIR"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP_DIR" "$ZIP"
fi
spctl --assess --type execute --verbose=4 "$APP_DIR" || true
