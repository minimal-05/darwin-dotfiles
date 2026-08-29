#!/usr/bin/env bash
#
# Screen recording, macOS version.
#
# The Linux original used wf-recorder + slurp + pactl, none of which exist here.
# `screencapture -v` records video and stops cleanly on SIGINT, so start/stop is
# the same toggle the shell already expects.
#
#   record.sh                       toggle: start a region recording, or stop one
#   record.sh --fullscreen          record the whole display
#   record.sh --region 'X,Y WxH'    record that rect (the shell passes this)
#   record.sh --sound               requested, but see the note below
#
# Sound: screencapture records video only. Capturing system audio on macOS needs
# a loopback device (BlackHole and a Multi-Output Device) which we will not
# install behind the user's back, so --sound records without audio and says so.

set -uo pipefail

# Qt's location, which is where the shell actually writes its config. Defaulting
# to ~/.config the way the Linux original did reads a file that does not exist.
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/Library/Preferences}"
CONFIG_FILE="$CONFIG_HOME/illogical-impulse/config.json"

CUSTOM_PATH="$(jq -r '.screenRecord.savePath // ""' "$CONFIG_FILE" 2>/dev/null)"
CUSTOM_PATH="${CUSTOM_PATH/#\~/$HOME}"
RECORDING_DIR="${CUSTOM_PATH:-$HOME/Movies}"

notify() { notify-send "$1" "$2" -a Recorder >/dev/null 2>&1 & disown; }

getdate() { date '+%Y-%m-%d_%H.%M.%S'; }

MANUAL_REGION=""
SOUND_FLAG=0
FULLSCREEN_FLAG=0
ARGS=("$@")
for ((i = 0; i < ${#ARGS[@]}; i++)); do
    case "${ARGS[i]}" in
        --region)
            if ((i + 1 < ${#ARGS[@]})); then
                MANUAL_REGION="${ARGS[i + 1]}"
            else
                notify "Recording cancelled" "No region specified for --region"
                exit 1
            fi
            ;;
        --sound)      SOUND_FLAG=1 ;;
        --fullscreen) FULLSCREEN_FLAG=1 ;;
    esac
done

# ---- stop an in-flight recording ----------------------------------------
# SIGINT is what finalises the movie file; SIGTERM would leave it truncated.
# A still capture is a `screencapture` process too, so matching the bare name
# calls a cmd+shift+3 screenshot a recording in progress -- only the -v form
# records video. Anchored with -x, because an unanchored -f match also hits any
# shell or editor whose own command line happens to mention the string.
VIDEO_PATTERN='(/[^ ]*)?/?screencapture -v.*'

if pgrep -fx "$VIDEO_PATTERN" >/dev/null 2>&1; then
    pkill -INT -fx "$VIDEO_PATTERN"
    notify "Recording stopped" "Drag the thumbnail somewhere, or let it save itself"
    exit 0
fi

# The shelf is where a finished capture waits while its thumbnail sits in the
# corner (modules/captureShelf). Recording writes straight into it, but under a
# hidden name: screencapture fills the file in over the whole recording, and the
# shelf's directory watcher would otherwise raise a thumbnail of a zero-length
# movie the moment recording started. The rename in finish() is what publishes
# it, and rename within one directory is atomic, so the watcher only ever sees
# a complete file.
SHELF="/tmp/quickshell/media/shelf"
mkdir -p "$SHELF" || { notify "Recording failed" "Cannot write to $SHELF"; exit 1; }
NAME="recording_$(getdate).mov"
STAGE="$SHELF/.$NAME"

# Nothing draws the shelf while the shell is down, so a recording started from a
# terminal would sit in /tmp until a reboot cleared it away. With no shell to
# hand it to, it goes straight to the save directory the way it used to.
finish() {
    if [ ! -s "$STAGE" ]; then
        rm -f "$STAGE"
        notify "Recording failed" "Nothing was captured"
        exit 1
    fi
    if pgrep -f 'quickshell .*shell\.qml' >/dev/null 2>&1; then
        mv "$STAGE" "$SHELF/$NAME"
    else
        mkdir -p "$RECORDING_DIR" && mv "$STAGE" "$RECORDING_DIR/$NAME"
        notify "Recording saved" "$RECORDING_DIR/$NAME"
    fi
}

[ "$SOUND_FLAG" -eq 1 ] && notify "Recording without sound" "macOS needs a loopback device to capture system audio"

# `screencapture -v` stops the instant stdin reports EOF, and the shell starts
# this detached with no terminal attached — a bare `screencapture -v` there
# records a fraction of a second and exits. A fifo held open read-write never
# reports EOF, and costs no extra process to keep alive. The redirect below is
# `<&3`, which inherits fd 3's read-write mode, so the recording's own stdin
# holds the write end and nothing can close it early.
FIFO="$(mktemp -u)"
if mkfifo "$FIFO" 2>/dev/null; then
    exec 3<>"$FIFO"
    rm -f "$FIFO"
else
    notify "Recording failed" "Could not create the stdin fifo"
    exit 1
fi

# `screencapture -v` is no longer exec'd: the script has to outlive it to do the
# rename above. The stop path pkills the child by its own anchored command line,
# so the extra bash in the middle changes nothing about how a recording is
# stopped.
if [ "$FULLSCREEN_FLAG" -eq 1 ] || [ -z "$MANUAL_REGION" ]; then
    notify "Starting recording" "$NAME"
    screencapture -v "$STAGE" <&3
    finish
    exit 0
fi

# The shell hands regions over in slurp's shape: "X,Y WxH". screencapture wants
# -R X,Y,W,H.
if [[ "$MANUAL_REGION" =~ ^([0-9]+),([0-9]+)[[:space:]]+([0-9]+)x([0-9]+)$ ]]; then
    RECT="${BASH_REMATCH[1]},${BASH_REMATCH[2]},${BASH_REMATCH[3]},${BASH_REMATCH[4]}"
else
    notify "Recording cancelled" "Could not read region '$MANUAL_REGION'"
    exit 1
fi

notify "Starting recording" "$NAME"
screencapture -v -R"$RECT" "$STAGE" <&3
finish
