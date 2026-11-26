#!/bin/bash
# Builds build/MouseJiggler.app from the Swift package (Command Line Tools are enough).
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/MouseJiggler"

APP="build/MouseJiggler.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/MouseJiggler"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc signature: no Apple developer certificate on this Mac.
# Consequence: every rebuild is a "new app" for macOS, so the Accessibility permission must be
# given again after installing a rebuilt copy.
codesign --force --sign - "$APP"
echo "Built $APP"

# ./build.sh --install : quit the running copy, move the fresh build into /Applications
# (the previously installed version goes to the Trash, recoverable), then start it.
if [[ "${1:-}" == "--install" ]]; then
    if pgrep -x MouseJiggler >/dev/null; then
        osascript -e 'quit app id "local.mousejiggler"' || true
        for _ in {1..20}; do pgrep -x MouseJiggler >/dev/null || break; sleep 0.25; done
    fi
    if [[ -e /Applications/MouseJiggler.app ]]; then
        mv /Applications/MouseJiggler.app "$HOME/.Trash/MouseJiggler $(date +%Y-%m-%d\ %H-%M-%S).app"
    fi
    # The old Accessibility entry belongs to the old build and no longer works (it can even look
    # switched on). Remove only MouseJiggler's entry, so macOS asks again cleanly.
    tccutil reset Accessibility local.mousejiggler || true
    mv "$APP" /Applications/
    echo "Installed /Applications/MouseJiggler.app"
    open /Applications/MouseJiggler.app
fi
