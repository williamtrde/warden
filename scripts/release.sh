#!/bin/bash
# Builds, signs, notarizes and staples Warden, then wraps it in a signed, notarized DMG.
# Needs a Developer ID Application identity and a `warden-notary` notarytool keychain profile.
set -euo pipefail
cd "$(dirname "$0")/.."

profile="${NOTARY_PROFILE:-warden-notary}"
identity="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -n 1)"
[ -n "$identity" ] || { echo "No Developer ID Application identity found." >&2; exit 1; }
team="$(printf '%s' "$identity" | sed -n 's/.*(\([A-Z0-9]*\))$/\1/p')"

rm -rf dist
mkdir -p dist
xcodegen generate --quiet
xcodebuild \
  -project Warden.xcodeproj \
  -scheme Warden \
  -configuration Release \
  -derivedDataPath build/DerivedData \
  -destination 'generic/platform=macOS' \
  -archivePath dist/Warden.xcarchive \
  CODE_SIGN_IDENTITY="$identity" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="$team" \
  OTHER_CODE_SIGN_FLAGS=--timestamp \
  archive | tail -n 3

# Stops with Apple's log when a submission is refused.
notarize() {
  local result id status
  result="$(xcrun notarytool submit "$1" --keychain-profile "$profile" --wait --output-format json)" || true
  id="$(plutil -extract id raw -o - - <<<"$result")"
  status="$(plutil -extract status raw -o - - <<<"$result")"
  echo "Notarization of $1: $status ($id)"
  if [ "$status" != "Accepted" ]; then
    xcrun notarytool log "$id" --keychain-profile "$profile" >&2
    exit 1
  fi
}

app=dist/Warden.app
cp -R dist/Warden.xcarchive/Products/Applications/Warden.app "$app"
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")"
dmg="dist/Warden-$version.dmg"

# Refuse early what notarization would refuse late.
codesign --verify --deep --strict "$app"
entitlements="$(codesign -d --entitlements - "$app" 2>/dev/null)"
case "$entitlements" in
  *get-task-allow*) echo "get-task-allow is present." >&2; exit 1 ;;
esac
[ "$(lipo -archs "$app/Contents/MacOS/Warden")" = "x86_64 arm64" ] || { echo "Not a universal binary." >&2; exit 1; }

ditto -c -k --keepParent "$app" dist/Warden.zip
notarize dist/Warden.zip
xcrun stapler staple "$app"
rm dist/Warden.zip

staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"
hdiutil create -volname Warden -srcfolder "$staging" -ov -format UDZO "$dmg" >/dev/null
codesign --sign "$identity" --timestamp "$dmg"
notarize "$dmg"
xcrun stapler staple "$dmg"

xcrun stapler validate "$app"
xcrun stapler validate "$dmg"
spctl --assess --type execute --verbose "$app"
spctl --assess --type open --context context:primary-signature --verbose "$dmg"
shasum -a 256 "$dmg"
