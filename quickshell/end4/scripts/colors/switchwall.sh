#!/usr/bin/env bash
#
# Wallpaper + Material You colour generation, macOS version.
#
# The Linux original (kept alongside as switchwall.linux.sh) drives matugen
# templates, KDE's kde-material-you-colors, GNOME gsettings and hyprctl. None of
# those exist here, and it aborted before doing anything — which is why the
# wallpaper thumbnail, the light/dark buttons, the palette picker and every
# parallax option did nothing.
#
# This does the three things the shell actually needs:
#   1. set the desktop picture (unless --noswitch)
#   2. generate the palette into the colors.json the shell watches
#   3. write background.wallpaperPath back into the shell's config
#
#   switchwall.sh                        pick an image, set it, regenerate
#   switchwall.sh <image>                set that image, regenerate
#   switchwall.sh --image <path>         same, the form the random-wallpaper
#                                        buttons use
#   switchwall.sh --noswitch             regenerate from the current wallpaper
#   switchwall.sh --mode dark|light      force light/dark
#   switchwall.sh --type scheme-content  force a palette variant

set -uo pipefail

# Qt's StandardPaths on macOS, which is what the QML side uses. The shell reads
# ~/Library/Preferences/illogical-impulse/config.json, so the script must too —
# defaulting to ~/.config the way the Linux original does reads a file that does
# not exist here.
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/Library/Preferences}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/Library/Preferences}"

SHELL_CONFIG_FILE="$CONFIG_HOME/illogical-impulse/config.json"
STATE_DIR="$STATE_HOME/quickshell/State/user/generated"
COLORS_FILE="$STATE_DIR/colors.json"
MODE_FILE="$STATE_DIR/mode.txt"

# qs-matugen lives in the quickshell-macos checkout, not inside this config, so
# no relative path from here stays true -- counting four directories up worked
# only while this config sat in that checkout, and broke silently the moment it
# moved. Take it from PATH, which qs-switch populates for everything the shell
# spawns, and fall back to the checkout for a plain terminal run.
MATUGEN="${QS_MATUGEN:-$(command -v qs-matugen 2>/dev/null)}"
[ -x "$MATUGEN" ] || MATUGEN="$HOME/Projects/quickshell-macos/bin/qs-matugen"

mode_flag=""
type_flag=""
noswitch=0
image=""
# Whether a specific image was named on the command line, as opposed to one
# discovered from the desktop or the config. An image the caller named and that
# turns out to be unusable is an error, not a cue to fall back to the accent.
requested=0

while [ $# -gt 0 ]; do
    case "$1" in
        --mode)     mode_flag="${2:-}"; shift 2 ;;
        --image)    image="${2:-}"; requested=1; shift 2 ;;
        --type)     type_flag="${2:-}"; shift 2 ;;
        --noswitch) noswitch=1; shift ;;
        --*)        shift ;;
        *)          image="$1"; requested=1; shift ;;
    esac
done

die() { echo "switchwall: $*" >&2; exit 1; }

[ -x "$MATUGEN" ] || die "colour generator not found at $MATUGEN"

mkdir -p "$STATE_DIR"

# ---- mode ----------------------------------------------------------------
# Remembered between runs so `--noswitch` alone (the palette picker) does not
# silently flip the theme.
if [ -z "$mode_flag" ]; then
    mode_flag="$(cat "$MODE_FILE" 2>/dev/null)"
    mode_flag="${mode_flag:-dark}"
fi
[ "$mode_flag" = "light" ] || mode_flag="dark"
printf '%s\n' "$mode_flag" > "$MODE_FILE"

# ---- palette variant -----------------------------------------------------
if [ -z "$type_flag" ] && [ -f "$SHELL_CONFIG_FILE" ]; then
    type_flag="$(jq -r '.appearance.palette.type // "auto"' "$SHELL_CONFIG_FILE" 2>/dev/null)"
fi

case "${type_flag:-auto}" in
    scheme-content)     scheme=content ;;
    scheme-expressive)  scheme=expressive ;;
    scheme-fidelity)    scheme=fidelity ;;
    scheme-fruit-salad) scheme=fruitsalad ;;
    scheme-monochrome)  scheme=monochrome ;;
    scheme-neutral)     scheme=neutral ;;
    scheme-rainbow)     scheme=rainbow ;;
    scheme-vibrant)     scheme=vibrant ;;
    *)                  scheme=tonalspot ;;   # "auto" and anything unknown
esac

# ---- choose the image ----------------------------------------------------
current_wallpaper() {
    osascript -e 'tell application "System Events" to get picture of current desktop' 2>/dev/null
}

if [ -z "$image" ] && [ "$noswitch" -eq 0 ]; then
    # No image and we are allowed to switch: ask for one. The Files app does the
    # asking rather than macOS's open panel, which is a Finder window in all but
    # name. It is asynchronous -- picking an image there runs this script again
    # with --image -- so this run stops here.
    FINDER="${QS_FINDER:-$(command -v qs-finder 2>/dev/null)}"
    [ -x "$FINDER" ] || FINDER="$HOME/Projects/quickshell-macos/bin/qs-finder"
    [ -x "$FINDER" ] || die "file manager not found at $FINDER"
    exec "$FINDER" --pick-wallpaper "$mode_flag"
fi

if [ -z "$image" ]; then
    # The recorded wallpaper wins over the live desktop picture.
    #
    # It used to be the other way round, on the reasoning that System Settings
    # or macOS's own rotation could change the picture behind the shell's back.
    # That reasoning does not survive Spaces. System Events exposes one
    # "desktop" per *display*, not per Space, so `set picture of every desktop`
    # only ever repaints the Space you are on, and `get picture of current
    # desktop` answers with whatever the Space you are on happens to show. On a
    # machine with several Spaces those disagree permanently, and reading the
    # live picture here meant a plain `--noswitch` (the light/dark buttons, the
    # palette picker) re-themed to whichever Space was focused at the time.
    #
    # background.wallpaperPath is the wallpaper the shell was actually told to
    # use, which is the thing the palette should follow. The live picture is
    # still the fallback for the case the record cannot cover: a first run, or
    # a config that has never had a wallpaper set.
    image="$(jq -r '.background.wallpaperPath // ""' "$SHELL_CONFIG_FILE" 2>/dev/null)"
    if [ -z "$image" ] || [ ! -f "$image" ]; then
        image="$(current_wallpaper)"
        [ -n "$image" ] && [ -f "$image" ] || image=""
    fi
fi

# ---- set the desktop picture --------------------------------------------
# Not `osascript ... set picture of every desktop`: System Events reaches only
# the Space being stood on, so every other Space, and SystemDefault -- the scope
# the login window draws from, before any session exists to have a Space -- kept
# whatever they last held. The shell paints its own background over the desktop,
# which hides the split until you log out and the login screen shows you the
# stale one. set-desktop-picture.py writes every scope in the store.
#
# Reported rather than discarded, unlike the osascript it replaces: a wallpaper
# the shell painted but macOS never got is the exact split this is here to close,
# and silence is what let it drift this far. Non-fatal all the same, since the
# shell's own background does not depend on it.
if [ "$noswitch" -eq 0 ] && [ -n "$image" ] && [ -f "$image" ]; then
    "$(dirname "${BASH_SOURCE[0]}")/set-desktop-picture.py" "$image" >/dev/null \
        || echo "switchwall: could not set the macOS desktop picture" >&2
fi

# ---- record the wallpaper in the shell's config --------------------------
# The shell watches this file, so writing it is what makes the preview
# thumbnail and every wallpaper-dependent option come alive.
#
# This has to happen *before* the palette generation below, not after it.
# WallpaperWatcher polls the live desktop picture every 5s and re-runs this
# script whenever it disagrees with background.wallpaperPath. Generating first
# left the two disagreeing for as long as matugen took -- seconds -- so a poll
# landing in that window fired a second switchwall against the image this run
# was already handling: two generators writing colors.json, and two
# read-modify-write cycles on the config that can drop each other's edits.
if [ -n "$image" ] && [ -f "$image" ] && [ -f "$SHELL_CONFIG_FILE" ]; then
    tmp="$SHELL_CONFIG_FILE.tmp.$$"
    if jq --arg p "$image" '.background.wallpaperPath = $p' "$SHELL_CONFIG_FILE" > "$tmp" 2>/dev/null; then
        mv "$tmp" "$SHELL_CONFIG_FILE"
    else
        rm -f "$tmp"
    fi
fi

# ---- generate the palette -----------------------------------------------
if [ -n "$image" ] && [ -f "$image" ]; then
    "$MATUGEN" --image "$image" --mode "$mode_flag" --scheme "$scheme" --out "$COLORS_FILE" >/dev/null \
        || die "colour generation failed for $image"
elif [ "$requested" -eq 1 ]; then
    # Asked for a specific image that is not a readable file. macOS reports a
    # *directory* as the desktop picture while its own wallpaper rotation is on,
    # and falling through to the accent below would quietly swap the palette the
    # user is actually looking at for a generic one. Leave colors.json alone.
    die "not a readable image: $image"
else
    # No image at all: a solid-colour or screen-saver desktop. Keep the theme
    # working off the accent.
    accent="$(jq -r '.appearance.palette.accentColor // ""' "$SHELL_CONFIG_FILE" 2>/dev/null)"
    [ -n "$accent" ] || accent="#8f7fd6"
    "$MATUGEN" --color "$accent" --mode "$mode_flag" --scheme "$scheme" --out "$COLORS_FILE" >/dev/null \
        || die "colour generation failed for $accent"
fi

# ---- repaint the apps that follow the palette ----------------------------
# The shell watches colors.json and repaints itself; kitty and Firefox cannot,
# so the palette has to be written into their own config formats. Reaching for
# a sibling of this script by name is safe -- unlike the walk up to bin/ that
# used to break here, apply-apps.py moves whenever switchwall.sh does.
#
# Non-fatal on purpose: a colour change that repainted the desktop but not the
# terminal is still a colour change, and should not report itself as failed.
"$(dirname "${BASH_SOURCE[0]}")/apply-apps.py" || echo "switchwall: app theming failed" >&2

echo "switchwall: mode=$mode_flag scheme=$scheme image=${image:-<none>}"
