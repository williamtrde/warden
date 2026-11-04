#!/bin/bash
# Safe demo: runs a Debug build against a throwaway fake home, then plays a silent config change.
# Your real files are never involved: only Debug builds honor WARDEN_HOME.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIGURATION=Debug scripts/build-app.sh
demo_home="$(mktemp -d)/home"
scripts/demo-home.sh "$demo_home"

WARDEN_HOME="$demo_home" WARDEN_OPEN_WINDOW=1 \
  build/DerivedData/Build/Products/Debug/Warden.app/Contents/MacOS/Warden &
app=$!
trap 'kill "$app" 2>/dev/null || true; rm -rf "$(dirname "$demo_home")"' EXIT

echo "Warden is running against $demo_home"
read -r -p "Press Return to play the silent change..."
scripts/demo-attack.sh "$demo_home"
read -r -p "Look at the menu bar icon and the main window. Press Return to quit..."
