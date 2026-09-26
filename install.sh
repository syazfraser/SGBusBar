#!/bin/zsh
# Builds a Release copy of SGBusBar, installs it in /Applications (replacing any older copy),
# and opens it. Run it again after changing the code to update the installed app.
set -euo pipefail
cd "$(dirname "$0")"

# Use Xcode's tools even if xcode-select points at the Command Line Tools.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

echo "Building SGBusBar (Release)…"
xcodebuild -project SGBusBar.xcodeproj -scheme SGBusBar -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath build -quiet build

# Quit any running copy, including one started from Xcode, so it can be replaced.
pkill -x SGBusBar 2>/dev/null && sleep 1 || true

rm -rf /Applications/SGBusBar.app
cp -R build/Build/Products/Release/SGBusBar.app /Applications/
open /Applications/SGBusBar.app

echo "Installed and opened /Applications/SGBusBar.app"
echo "To start it at login: SGBusBar Settings > General > Launch at Login."
