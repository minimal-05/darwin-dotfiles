#!/usr/bin/env bash
# Random SFW wallpaper from wallhaven.
#   $1  search query, "" for none (default: minimalism)
#   $2  category bitmask "general anime people" (default: 100, general only)
# purity=100 pins results to "sfw", so nothing spicy comes back whichever
# category is asked for -- and that combination needs no API key.

QUERY="${1-minimalism}"
CATEGORIES="${2:-100}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WALLPAPER_DIR="$HOME/Pictures/Wallpapers"

mkdir -p "$WALLPAPER_DIR"

link=$(curl -sf --get "https://wallhaven.cc/api/v1/search" \
    --data-urlencode "q=$QUERY" \
    -d "categories=$CATEGORIES&purity=100&sorting=random&atleast=1920x1080" \
    | jq -r '.data[0].path // empty')

if [ -z "$link" ]; then
    echo "No wallhaven result for '$QUERY' (categories=$CATEGORIES)" >&2
    exit 1
fi

# A fresh name for every download.
#
# This used to write one of two fixed names, random_wallpaper.EXT and
# random_wallpaper-1.EXT, alternating whenever the first already matched
# background.wallpaperPath. That comparison included the extension, so a run
# that came back with a different file type never matched and happily
# overwrote a name macOS was still showing -- and even with matching
# extensions, alternating only pushed the collision out by one pick.
#
# macOS stores the desktop picture as a *path*, per desktop, and re-reads it on
# space switches, wake and login. Rewriting the bytes under a live path is
# exactly the "wallpaper changed on its own" symptom: nothing set a new
# wallpaper, the old one just became a different image. Unique names make that
# impossible -- no path is ever written twice.
downloadPath="$WALLPAPER_DIR/random_wallpaper-$(date +%Y%m%d-%H%M%S)-$$.${link##*.}"

curl -sf "$link" -o "$downloadPath" || { echo "Download failed: $link" >&2; exit 1; }
"$SCRIPT_DIR/../switchwall.sh" --image "$downloadPath"

# ponytail: keep the 10 newest, delete the rest. Unique names would otherwise
# fill Wallpapers/ forever. The glob only matches the dated form, so the old
# random_wallpaper.EXT / random_wallpaper-1.EXT files -- one of which may still
# be the live desktop picture -- are left alone.
ls -t "$WALLPAPER_DIR"/random_wallpaper-*-*-*.* 2>/dev/null | tail -n +11 | while IFS= read -r old; do
    rm -f "$old"
done
