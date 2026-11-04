#!/bin/bash
# Builds an unsigned universal Release app into build/. Used by CI and for local checks.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate --quiet
xcodebuild \
  -project Warden.xcodeproj \
  -scheme Warden \
  -configuration "${CONFIGURATION:-Release}" \
  -derivedDataPath build/DerivedData \
  -destination 'generic/platform=macOS' \
  CODE_SIGN_IDENTITY=- \
  build | tail -n 3
