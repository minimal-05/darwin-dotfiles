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

# screencapture's pid while a recording runs. services/ScreenRecording.qml
# watches this file instead of polling pgrep; the directory is the same
# runtime dir `qs` exports, with its default for a run from a terminal.
PIDFILE="${XDG_RUNTIME_DIR:-/tmp/quickshell-$UID}/quickshell/recording.pid"

# Run screencapture as a child rather than exec'ing over this script, so the
# pidfile can be removed once it exits. SIGINT is what finalises the movie.
record() {
    mkdir -p "$(dirname "$PIDFILE")"
    screencapture "$@" &
    local child=$!
    echo "$child" > "$PIDFILE"
    trap 'kill -INT "$child" 2>/dev/null' INT TERM
    wait "$child"
    rm -f "$PIDFILE"
}

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
# The pidfile names our own recording; pgrep is the fallback for one started
# some other way (or a pidfile left by a screencapture that died).
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null; then
    kill -INT "$(cat "$PIDFILE")"
    notify "Recording stopped" "Saved to $RECORDING_DIR"
    exit 0
fi
rm -f "$PIDFILE"
if pgrep -x screencapture >/dev/null 2>&1; then
    pkill -INT -x screencapture
    notify "Recording stopped" "Saved to $RECORDING_DIR"
    exit 0
fi

mkdir -p "$RECORDING_DIR" || { notify "Recording failed" "Cannot write to $RECORDING_DIR"; exit 1; }
OUT="$RECORDING_DIR/recording_$(getdate).mov"

[ "$SOUND_FLAG" -eq 1 ] && notify "Recording without sound" "macOS needs a loopback device to capture system audio"

if [ "$FULLSCREEN_FLAG" -eq 1 ] || [ -z "$MANUAL_REGION" ]; then
    notify "Starting recording" "$(basename "$OUT")"
    record -v "$OUT"
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

notify "Starting recording" "$(basename "$OUT")"
record -v -R"$RECT" "$OUT"
