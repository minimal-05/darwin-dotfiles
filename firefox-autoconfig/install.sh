#!/usr/bin/env bash
# Reinstall the ComicShanns font-toggle autoconfig into Firefox.app.
# Run this after a Firefox update (updates overwrite the app bundle).
set -e
RES="/Applications/Firefox.app/Contents/Resources"
HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$RES/defaults/pref"
cp "$HERE/autoconfig.js" "$RES/defaults/pref/autoconfig.js"
cp "$HERE/firefox.cfg" "$RES/firefox.cfg"
echo "Autoconfig reinstalled. Fully quit and relaunch Firefox."
