#!/usr/bin/env bash
# Random SFW wallpaper from wallhaven.
#   $1  search query, "" for none (default: minimalism)
#   $2  category bitmask "general anime people" (default: 100, general only)
#
# Results are sorted by all-time favourites and drawn from a random slot within
# the top MAX_PAGES pages, so what lands is something people actually liked
# rather than whatever sorting=random dredges up. purity=100 pins every result
# to "sfw", and ratios/atleast keep it desktop-shaped instead of phone-vertical.
# That combination needs no API key.
# ponytail: MAX_PAGES is the quality/variety dial -- lower it for a tighter
# "best of" pool, raise it for more variety at lower average favourites.

QUERY="${1-minimalism}"
CATEGORIES="${2:-100}"
MAX_PAGES=40

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WALLPAPER_DIR="$HOME/Pictures/Wallpapers"
FILTERS="categories=$CATEGORIES&purity=100&sorting=favorites&atleast=1920x1080&ratios=16x9,16x10"

mkdir -p "$WALLPAPER_DIR"

fetch_page() {
    curl -sf --get "https://wallhaven.cc/api/v1/search" \
        --data-urlencode "q=$QUERY" -d "$FILTERS&page=$1"
}

first=$(fetch_page 1)
if [ -z "$first" ]; then
    echo "wallhaven request failed" >&2
    exit 1
fi

last=$(jq -r '.meta.last_page // 1' <<< "$first")
[[ "$last" =~ ^[0-9]+$ ]] && [ "$last" -ge 1 ] || last=1
[ "$last" -gt "$MAX_PAGES" ] && last=$MAX_PAGES

page=$((1 + RANDOM % last))
if [ "$page" -eq 1 ]; then resp="$first"; else resp=$(fetch_page "$page"); fi

count=$(jq '.data | length' <<< "$resp")
[[ "$count" =~ ^[0-9]+$ ]] || count=0
if [ "$count" -eq 0 ]; then
    echo "No wallhaven result for '$QUERY' (categories=$CATEGORIES)" >&2
    exit 1
fi

link=$(jq -r ".data[$((RANDOM % count))].path" <<< "$resp")

# A fresh name for every download.
#
# This used to write one of two fixed names, random_wallpaper.EXT and
# random_wallpaper-1.EXT, alternating whenever the first already matched
# background.wallpaperPath. That comparison included the extension, so a run
# that came back with a different file type never matched and happily overwrote
# a name macOS was still showing -- and even with matching extensions,
# alternating only pushed the collision out by one pick.
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
