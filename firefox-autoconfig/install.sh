#!/usr/bin/env bash
# Reinstall the autoconfig into Firefox.app: the ComicShanns font toggle and
# the live palette reload, which is what lets a colour change reach an already
# running browser.
# Run this after a Firefox update (updates overwrite the app bundle).
set -e
RES="/Applications/Firefox.app/Contents/Resources"
HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$RES/defaults/pref"
cp "$HERE/autoconfig.js" "$RES/defaults/pref/autoconfig.js"
cp "$HERE/firefox.cfg" "$RES/firefox.cfg"
echo "Autoconfig reinstalled. Fully quit and relaunch Firefox once;"
echo "after that, colour changes apply without a restart."
