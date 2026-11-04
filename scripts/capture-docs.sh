#!/bin/bash
# Regenerates docs/ screenshots and the GIF from the fake demo home.
# Captures the Warden window only, never the desktop. Needs Screen Recording permission.
set -euo pipefail
cd "$(dirname "$0")/.."

work="$(mktemp -d)"
demo_home="$work/home"
CONFIGURATION=Debug scripts/build-app.sh
scripts/demo-home.sh "$demo_home"

WARDEN_HOME="$demo_home" WARDEN_OPEN_WINDOW=1 \
  build/DerivedData/Build/Products/Debug/Warden.app/Contents/MacOS/Warden -AppleLanguages '(en)' &
app=$!
trap 'kill "$app" 2>/dev/null || true; rm -rf "$work"' EXIT
sleep 4

shoot() {
  local id
  id="$(swift scripts/window-id.swift "$app")"
  screencapture -x -o -l "$id" "$1"
}

mkdir -p docs
shoot "$work/1.png"
scripts/demo-attack.sh "$demo_home"
sleep 5
shoot "$work/2.png"
cp "$work/1.png" docs/compliant.png
cp "$work/2.png" docs/critical-change.png
swift scripts/make-gif.swift docs/demo.gif 900 2.5 "$work/1.png" "$work/2.png"
