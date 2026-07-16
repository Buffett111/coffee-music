#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
VERSION="${VERSION:-1.0.0}"
BUILD_ROOT="$ROOT/build/DerivedData"
APP="$BUILD_ROOT/Build/Products/Release/CoffeeSync.app"
DIST="$ROOT/dist"
STAGE="$ROOT/build/dmg-stage"
DMG="$DIST/CoffeeSync-$VERSION.dmg"

cd "$ROOT"
rm -rf "$BUILD_ROOT"
rm -rf "$STAGE"
mkdir -p "$STAGE" "$DIST"

xcodebuild \
  -project CoffeeSync.xcodeproj \
  -scheme CoffeeSync \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$BUILD_ROOT" \
  build CODE_SIGNING_ALLOWED=NO MARKETING_VERSION="$VERSION" \
  ENABLE_CODE_COVERAGE=NO \
  CLANG_ENABLE_CODE_COVERAGE=NO \
  GCC_GENERATE_TEST_COVERAGE_FILES=NO \
  GCC_INSTRUMENT_PROGRAM_FLOW_ARCS=NO

test -d "$APP"
ditto "$APP" "$STAGE/CoffeeSync.app"

# The Xcode build embeds source locations in debug information.  Strip it
# before signing so a distributable DMG does not disclose local build paths.
strip -S "$STAGE/CoffeeSync.app/Contents/MacOS/CoffeeSync"
"$ROOT/scripts/sanitize-shazam-runtime.py" \
  "$STAGE/CoffeeSync.app/Contents/Resources/ShazamIO/python"

# Ad-hoc signing permits a locally built app bundle to be moved between Macs.
# It is intentionally not a replacement for Developer ID signing/notarization.
codesign --force --deep --sign - "$STAGE/CoffeeSync.app"
codesign --verify --deep --strict "$STAGE/CoffeeSync.app"
"$ROOT/scripts/verify-release-clean.sh" "$STAGE/CoffeeSync.app"

ln -s /Applications "$STAGE/Applications"
rm -f "$DMG" "$DIST/SHA256SUMS"
hdiutil create -quiet -volname "CoffeeSync" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
(cd "$DIST" && shasum -a 256 "$(basename "$DMG")" > SHA256SUMS)

echo "Created: $DMG"
echo "Checksum: $DIST/SHA256SUMS"
