#!/usr/bin/env bash
# Install build/sioyek.app to /Applications/sioyek.app.
#
# Assumes ./build_mac.sh (or ./build_mac.sh nodmg) has already produced
# a deployed bundle at build/sioyek.app -- if you skipped macdeployqt,
# the app will crash on launch with "cannot load cocoa platform plugin".
#
# Usage:
#   ./install_mac.sh           # standard install
#   ./install_mac.sh --quiet   # suppress all output unless something fails

set -e

QUIET=0
if [ "$1" = "--quiet" ] || [ "$1" = "-q" ]; then
    QUIET=1
fi

log() {
    if [ $QUIET -eq 0 ]; then
        echo "$@"
    fi
}

# 1. Verify the build exists and has Qt frameworks embedded.
if [ ! -x build/sioyek.app/Contents/MacOS/sioyek ]; then
    echo "error: build/sioyek.app/Contents/MacOS/sioyek not found. Run ./build_mac.sh first." >&2
    exit 1
fi
if [ ! -f build/sioyek.app/Contents/PlugIns/platforms/libqcocoa.dylib ]; then
    echo "error: build/sioyek.app/Contents/PlugIns/platforms/libqcocoa.dylib missing -- macdeployqt didn't run." >&2
    echo "       Re-run ./build_mac.sh (without skipping macdeployqt) to embed Qt frameworks." >&2
    exit 1
fi

# 2. Kill any running sioyek so we can overwrite the bundle.
if pgrep -x sioyek >/dev/null 2>&1; then
    log "Stopping running sioyek..."
    pkill -x sioyek 2>/dev/null || true
    sleep 1
fi

# 3. Remove the Homebrew cask version if installed, so we own /Applications/sioyek.app.
if brew list --cask sioyek >/dev/null 2>&1; then
    log "Uninstalling Homebrew cask sioyek..."
    brew uninstall --cask sioyek >/dev/null 2>&1 || true
fi

# 4. Replace the bundle.
log "Installing to /Applications/sioyek.app..."
rm -rf /Applications/sioyek.app
cp -R build/sioyek.app /Applications/

log "Done. Launch with: open /Applications/sioyek.app"
