#!/usr/bin/env bash
# Study mode: hide everything and allow only the sites on the school list until
# the timer runs out.
#
#   study-mode.sh start [minutes]   begin a session
#   study-mode.sh stop              the escape hatch -- ends it early
#   study-mode.sh status            json for the bar (also cleans up a dead session)
#
# Apps are *hidden*, not quit, and Firefox's tabs are never touched: nothing can
# be lost, and everything is where you left it when the session ends.
#
# Ending early is deliberate rather than accidental: Settings has an End button
# and this script has `stop`. The bar button has no stop path, so a stray click
# cannot undo a session -- but a lock you cannot get out of is a trap, so a
# reboot ends it too (status notices the timer is gone and cleans up).
#
# Blocking is Firefox's own WebsiteFilter enterprise policy: no sudo, no hosts
# file, and it cannot be turned off from inside the browser. It only covers
# Firefox -- another browser is a way around this, by construction.
set -uo pipefail

STATE_DIR="$HOME/.local/state/quickshell/study-mode"
STATE="$STATE_DIR/state.json"
STATS="$STATE_DIR/stats.json"
POLICY_DIR="/Applications/Firefox.app/Contents/Resources/distribution"
POLICY="$POLICY_DIR/policies.json"
POLICY_BAK="$STATE_DIR/policies-backup.json"
CONFIG="$HOME/Library/Preferences/illogical-impulse/config.json"
FF_RE='Firefox.app/Contents/MacOS/firefox( |$)'

# Focus watcher knobs. ponytail: a static screen plus no input is the whole
# definition of "not studying" -- no OCR, no model. A lecture video keeps the
# screen moving, so it counts; a nudge of the mouse clears an idle warning.
IDLE_LIMIT=180        # seconds without keyboard/mouse input
STATIC_RMSE=0.004     # below this, two 48x48 grey frames are "the same screen"
POINTS_PER_MIN=1
COMPLETE_BONUS=25

# Apps that must survive: the shell draws the bar, Finder is the desktop, and
# Firefox is the one browser the session is built around.
KEEP_RE='^(quickshell|quickshell-engine|Finder|[Ff]irefox|loginwindow|SystemUIServer|Dock)$'

die() { echo "$*" >&2; exit 1; }

# Only the apps actually on screen: one already hidden was not hidden by us and
# must not be revealed at the end.
running_apps() {
    osascript -e 'tell application "System Events" to get name of every process whose background only is false and visible is true' 2>/dev/null \
        | tr ',' '\n' | sed 's/^ *//;s/ *$//' | grep -vE "$KEEP_RE" | grep -v '^$'
}

# Show or hide a list of apps (one per line) in a single osascript call.
set_visible() {
    local list
    list=$(grep -v '^$' <<< "$2" | jq -R . | jq -rs 'map(tojson) | join(", ")')
    [ -n "$list" ] || return 0
    osascript -e "tell application \"System Events\" to set visible of (every process whose name is in {$list}) to $1" >/dev/null 2>&1
}

# The command line of every running Firefox, one per line -- usually skhd's
# `--no-remote -P default` + `--single-instance -P default-release` pair -- so
# the relaunch brings back the same profiles, not whatever `open -a` picks.
firefox_cmds() {
    local pid
    for pid in $(pgrep -f "$FF_RE"); do ps -o args= -p "$pid"; done
}

# terminate() reaches every instance at once (`tell application "Firefox" to
# quit` only reaches one). Two seconds for a clean quit, then SIGTERM: tabs are
# safe either way -- Firefox checkpoints them every 15s and restores them.
quit_firefox() {
    local i
    osascript -l JavaScript -e 'ObjC.import("AppKit"); $.NSRunningApplication.runningApplicationsWithBundleIdentifier("org.mozilla.firefox").js.forEach(a => a.terminate)' >/dev/null 2>&1
    for i in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -qf "$FF_RE" || return 0
        [ "$i" = 5 ] && pkill -TERM -f "$FF_RE"
        sleep 0.4
    done
    ! pgrep -qf "$FF_RE"
}

# MOZ_DISABLE_SAFE_MODE_KEY: holding Option (the hyper key includes it) while
# Firefox starts opens the Troubleshoot Mode prompt instead of the browser.
# --no-remote instances first, as skhd's launcher does; nothing recorded falls
# back to that launcher.
launch_firefox() {
    local cmds="$1" cmd
    if [ -z "$cmds" ]; then
        MOZ_DISABLE_SAFE_MODE_KEY=1 nohup "$HOME/.config/skhd/firefox-smart-launch.sh" >/dev/null 2>&1 &
        return
    fi
    while IFS= read -r cmd; do
        [ -n "$cmd" ] || continue
        # Word splitting on purpose: "…/firefox --no-remote -P default".
        MOZ_DISABLE_SAFE_MODE_KEY=1 nohup $cmd >/dev/null 2>&1 &
        case "$cmd" in *--no-remote*) sleep 1 ;; esac
    done < <(grep -- '--no-remote' <<< "$cmds"; grep -v -- '--no-remote' <<< "$cmds")
}

# Relaunching is only needed if Firefox is running: policies.json is read at
# startup. A Firefox that is not running picks it up whenever it next starts.
restart_firefox() {
    local ff="$1"
    pgrep -qf "$FF_RE" || return 0
    [ -n "$ff" ] || ff=$(firefox_cmds)
    quit_firefox || return 1
    launch_firefox "$ff"
}

# The allowlist policy. DisableAppUpdate too: an update staged before the
# session is applied on the next launch by swapping in a copy of the app bundle
# taken before this file existed, which silently deletes it.
write_policy() {
    local sites
    sites=$(jq -c '[.studyMode.allowedSites[]? // empty]' "$CONFIG" 2>/dev/null)
    [ -n "$sites" ] && [ "$sites" != "[]" ] || return 1
    mkdir -p "$POLICY_DIR" && jq -n --argjson s "$sites" \
        '{policies:{DisableAppUpdate:true, WebsiteFilter:{Block:["<all_urls>"],Exceptions:$s}}}' > "$POLICY"
}

restore_policy() {
    if [ -f "$POLICY_BAK" ]; then mv "$POLICY_BAK" "$POLICY"; else rm -f "$POLICY"; fi
}

# Stats outlive sessions: {points, sessions, warnings, days:{"YYYY-MM-DD":minutes}}.
bump_stats() {
    mkdir -p "$STATE_DIR"
    jq -e . "$STATS" >/dev/null 2>&1 || echo '{"points":0,"sessions":0,"warnings":0,"days":{}}' > "$STATS"
    jq "$1" "$STATS" > "$STATS.$$" && mv "$STATS.$$" "$STATS"
}

set_state() {
    jq "$@" "$STATE" > "$STATE.$$" && mv "$STATE.$$" "$STATE"
}

# Grey 48x48 thumbnail of the main display minus the top 6% (the bar clock would
# otherwise make every minute look "changed"). Fails without Screen Recording
# permission -- the caller treats that as "moving", never as idle.
frame() {
    local raw="$STATE_DIR/raw.png"
    screencapture -x -t png "$raw" 2>/dev/null && [ -s "$raw" ] || return 1
    magick "$raw" -gravity south -crop 100%x94%+0+0 +repage \
        -resize '48x48!' -colorspace gray "$1" 2>/dev/null
    rm -f "$raw"
}

# The session's helpers (timer, guard, watch) are recorded by pid and killed
# first thing on stop. Before that, a timer from an ended session could fire
# into the next one and end it early, and the guard could put the block back
# in the gap between stop removing it and the state file going.
kill_helpers() {
    local pid
    for pid in $(jq -r '.pids[]?' "$STATE" 2>/dev/null); do
        [ "$pid" = "$$" ] && continue    # the timer execs into `stop done`: that is us
        pkill -P "$pid" 2>/dev/null; kill "$pid" 2>/dev/null
    done
}

case "${1:-}" in
start)
    [ -f "$STATE" ] && die "A session is already running."
    mins="${2:-}"
    [ -z "$mins" ] && mins=$(jq -r '.studyMode.durationMinutes // 50' "$CONFIG" 2>/dev/null)
    [[ "$mins" =~ ^[0-9]+$ ]] && [ "$mins" -gt 0 ] || die "Bad duration: $mins"

    mkdir -p "$STATE_DIR"
    [ -f "$POLICY" ] && cp "$POLICY" "$POLICY_BAK"
    # An empty allowlist would block the entire web -- a lockout, not a session.
    write_policy || { rm -f "$POLICY_BAK"; die "No allowed sites are set, so nothing was blocked. Add some under studyMode.allowedSites."; }

    apps="$(running_apps)"
    ff="$(firefox_cmds)"
    ends=$(( $(date +%s) + mins * 60 ))
    jq -n --argjson e "$ends" --arg a "$apps" --arg f "$ff" \
        '{active:true, endsAt:$e, apps:($a|split("\n")|map(select(length>0))), firefox:($f|split("\n")|map(select(length>0))), pids:[]}' > "$STATE"

    set_visible false "$apps" &
    if ! restart_firefox "$ff"; then
        restore_policy; wait; set_visible true "$apps"; rm -f "$STATE"
        die "Firefox would not quit, so nothing was blocked. Close it and try again."
    fi
    wait

    # The timer is a plain detached sleep; it dies with a reboot, and status
    # then cleans up.
    nohup bash -c "sleep $((mins * 60)); exec '$0' stop done" >/dev/null 2>&1 & t=$!
    nohup "$0" guard >/dev/null 2>&1 & g=$!
    nohup "$0" watch >/dev/null 2>&1 & w=$!
    set_state --argjson p "[$t,$g,$w]" '.pids = $p'
    echo "started for ${mins}m"
    ;;

stop)
    [ -f "$STATE" ] || die "No session is running."
    kill_helpers
    # Only a timer that actually ran out earns the bonus.
    if [ "${2:-}" = done ] && [ "$(date +%s)" -ge $(( $(jq -r '.endsAt' "$STATE") - 5 )) ]; then
        bump_stats ".points += $COMPLETE_BONUS | .sessions += 1"
    fi
    apps=$(jq -r '.apps[]?' "$STATE")
    ff=$(jq -r '.firefox[]?' "$STATE")
    rm -f "$STATE" "$STATE_DIR"/prev.png "$STATE_DIR"/cur.png

    restore_policy
    set_visible true "$apps" &
    restart_firefox "$ff"
    wait
    echo "stopped"
    ;;

guard)
    # Hiding is not a lock: Cmd+Tab or a Dock click brings an app straight back,
    # so re-hide on a slow loop. The shell is never in the list, so Settings and
    # its End button stay reachable.
    while [ -f "$STATE" ]; do
        # Something deleted the policy mid-session (a Firefox update, a
        # reinstall): put it back and restart Firefox so it is read.
        if [ ! -f "$POLICY" ] && write_policy; then
            restart_firefox ""
        fi
        set_visible false "$(jq -r '.apps[]?' "$STATE" 2>/dev/null)"
        sleep 2
    done
    ;;

watch)
    # Once a minute: is a study app in front, and is anyone there? A focused
    # minute earns XP. Going off-task warns once, with a sound, and then stays
    # quiet until you are back -- not a chime every minute you are away.
    study_re="$KEEP_RE"
    extra=$(jq -r '.studyMode.studyApps[]? // empty' "$CONFIG" 2>/dev/null | paste -sd'|' -)
    [ -n "$extra" ] && study_re="$KEEP_RE|^($extra)\$"
    prev="$STATE_DIR/prev.png" cur="$STATE_DIR/cur.png"
    rm -f "$prev"
    last=""
    while sleep 60 && [ -f "$STATE" ]; do
        front=$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null)
        # Locked or screensaver: not studying, not slacking either. No XP, no
        # warning, and the screen diff starts over when you are back.
        if [ "$front" = loginwindow ] || pgrep -xq ScreenSaverEngine; then
            rm -f "$prev"; last=""; continue
        fi
        idle=$(ioreg -c IOHIDSystem | awk '/HIDIdleTime/ {print int($NF/1000000000); exit}')
        moving=1
        if frame "$cur"; then
            if [ -f "$prev" ]; then
                rmse=$(magick compare -metric RMSE "$prev" "$cur" null: 2>&1 | awk -F'[()]' '{print $2}')
                awk -v r="${rmse:-1}" -v t="$STATIC_RMSE" 'BEGIN{exit !(r<t)}' && moving=0
            fi
            mv "$cur" "$prev"
        fi

        warn="" kind=""
        if [ -n "$front" ] && ! grep -qE "$study_re" <<< "$front"; then
            warn="$front isn't on your study list" kind="app:$front"
        elif [ "${idle:-0}" -ge "$IDLE_LIMIT" ] && [ "$moving" = 0 ]; then
            warn="No activity for $((idle / 60)) min. Still there?" kind="idle"
        fi

        if [ -z "$warn" ]; then
            bump_stats ".points += $POINTS_PER_MIN | .days[\"$(date +%F)\"] += 1"
        elif [ "$kind" != "$last" ]; then
            bump_stats '.warnings += 1'
            set_state --arg w "$warn" --argjson at "$(date +%s)" '.warn = {text:$w, at:$at}'
            afplay /System/Library/Sounds/Funk.aiff >/dev/null 2>&1 &
        fi
        last="$kind"
    done
    rm -f "$prev" "$cur"
    ;;

status)
    stats=$(jq -c . "$STATS" 2>/dev/null) || stats='{}'
    [ -n "$stats" ] || stats='{}'
    if [ -f "$STATE" ]; then
        # A session whose timer is gone (a reboot, a killed process) would
        # otherwise block Firefox forever. Give a fresh start a moment to
        # record its pids first.
        timer=$(jq -r '.pids[0] // empty' "$STATE" 2>/dev/null)
        age=$(( $(date +%s) - $(stat -f %m "$STATE") ))
        if { [ -n "$timer" ] && ! ps -o args= -p "$timer" 2>/dev/null | grep -q 'stop done'; } \
            || { [ -z "$timer" ] && [ "$age" -gt 30 ]; }; then
            "$0" stop >/dev/null 2>&1
        fi
    fi
    if [ -f "$STATE" ]; then
        jq --argjson now "$(date +%s)" --argjson s "$stats" \
            '{active:true, endsAt:.endsAt, remaining:(.endsAt-$now), warn:(.warn // null), stats:$s}' "$STATE"
    else
        jq -n --argjson s "$stats" '{active:false, remaining:0, stats:$s}'
    fi
    ;;
*) die "usage: study-mode.sh start [minutes] | stop | status" ;;
esac
