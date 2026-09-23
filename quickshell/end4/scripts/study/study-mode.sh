#!/usr/bin/env bash
# Study mode: hide everything, strip Firefox to one blank tab, and allow only
# the sites on the school list until the timer runs out.
#
# Apps are *hidden*, not quit. Nothing is closed, nothing can lose unsaved work,
# and everything is exactly where you left it when the session ends -- the point
# is that it is out of reach, not that it is gone.
#
#   study-mode.sh start [minutes]   begin a session
#   study-mode.sh stop              the escape hatch -- ends it early
#   study-mode.sh status            json for the bar
#
# Ending early is deliberate rather than accidental: Settings has an End button,
# this script has `stop`, and a reboot ends it too, because the timer lives in a
# process rather than a launchd job. The bar button itself has no stop path, so
# a stray click cannot undo a session -- but a lock you cannot get out of when
# something goes wrong is a trap, not a tool.
#
# Blocking is Firefox's own WebsiteFilter enterprise policy: no sudo, no hosts
# file, and it cannot be turned off from inside the browser. It only covers
# Firefox -- another browser is a way around this, by construction.
set -uo pipefail

STATE_DIR="$HOME/.local/state/quickshell/study-mode"
STATE="$STATE_DIR/state.json"
SESSION_BAK="$STATE_DIR/session-backup"
POLICY_DIR="/Applications/Firefox.app/Contents/Resources/distribution"
POLICY="$POLICY_DIR/policies.json"
POLICY_BAK="$STATE_DIR/policies-backup.json"
CONFIG="$HOME/Library/Preferences/illogical-impulse/config.json"
FF="/Applications/Firefox.app/Contents/MacOS/firefox"
STATS="$STATE_DIR/stats.json"

# Focus watcher knobs. ponytail: a static screen plus no input is the whole
# definition of "not studying" -- no OCR, no model. A lecture video keeps the
# screen moving, so it counts; reading one page for 3 minutes without touching
# anything does not, and a nudge of the mouse clears it.
IDLE_LIMIT=180        # seconds without keyboard/mouse input
STATIC_RMSE=0.004     # below this, two 48x48 grey frames are "the same screen"
POINTS_PER_MIN=1
COMPLETE_BONUS=25

# Apps that must survive: the shell itself draws the bar, Finder is the desktop,
# and Firefox is the one browser the session is built around.
KEEP_RE='^(quickshell|quickshell-engine|Finder|[Ff]irefox|loginwindow|SystemUIServer|Dock)$'

die() { echo "study-mode: $*" >&2; exit 1; }

# The profile Firefox actually launches. The [Install...] section wins over a
# Profile block's Default=1 -- that is the one the browser opens, so it is the
# one whose tabs are ours to put back.
default_profile() {
    local ini="$HOME/Library/Application Support/Firefox/profiles.ini" p
    p=$(awk -F= '/^\[Install/{i=1;next} i&&/^Default=/{print $2;exit}' "$ini" 2>/dev/null)
    [ -z "$p" ] && p=$(awk -F= '/^Path=/{path=$2} /^Default=1/{print path;exit}' "$ini" 2>/dev/null)
    [ -n "$p" ] && echo "$HOME/Library/Application Support/Firefox/$p"
}

# Only the ones actually on screen: an app already hidden was not hidden by us
# and must not be revealed at the end.
running_apps() {
    osascript -e 'tell application "System Events" to get name of every process whose background only is false and visible is true' 2>/dev/null \
        | tr ',' '\n' | sed 's/^ *//;s/ *$//' | grep -vE "$KEEP_RE" | grep -v '^$'
}

# Firefox does not reliably honour a plain `quit`: with several tabs open it
# raises a "close N tabs?" confirmation and simply stays running. The quit was
# being issued, swallowed, and the session then carried on around a browser that
# had never restarted -- so policies.json (only read at startup) was ignored, the
# tabs were never stripped, and every site still loaded. Ask nicely, wait, then
# insist with SIGTERM, which still lets it write its session out.
quit_firefox() {
    osascript -e 'tell application "Firefox" to quit' >/dev/null 2>&1
    for _ in $(seq 1 20); do
        pgrep -f "Firefox.app/Contents/MacOS/firefox" >/dev/null 2>&1 || return 0
        sleep 0.5
    done
    pkill -f "Firefox.app/Contents/MacOS/firefox" >/dev/null 2>&1
    for _ in $(seq 1 20); do
        pgrep -f "Firefox.app/Contents/MacOS/firefox" >/dev/null 2>&1 || return 0
        sleep 0.5
    done
    return 1
}

# Stats outlive sessions: {points, sessions, warnings, days:{"YYYY-MM-DD":minutes}}.
bump_stats() {
    mkdir -p "$STATE_DIR"
    [ -f "$STATS" ] || echo '{"points":0,"sessions":0,"warnings":0,"days":{}}' > "$STATS"
    jq "$1" "$STATS" > "$STATS.tmp" && mv "$STATS.tmp" "$STATS"
}

# Grey 48x48 thumbnail of the main display minus the top 6% (the bar clock would
# otherwise make every minute look "changed"). Empty on failure, e.g. no Screen
# Recording permission -- the caller treats that as "moving", never as idle.
frame() {
    local raw="$STATE_DIR/raw.png"
    screencapture -x -t png "$raw" 2>/dev/null && [ -s "$raw" ] || return 1
    magick "$raw" -gravity south -crop 100%x94%+0+0 +repage \
        -resize '48x48!' -colorspace gray "$1" 2>/dev/null
    rm -f "$raw"
}

case "${1:-}" in
start)
    [ -f "$STATE" ] && die "already running -- 'study-mode.sh stop' ends it"
    mins="${2:-}"
    [ -z "$mins" ] && mins=$(jq -r '.studyMode.durationMinutes // 50' "$CONFIG" 2>/dev/null)
    [[ "$mins" =~ ^[0-9]+$ ]] && [ "$mins" -gt 0 ] || die "bad duration: $mins"

    # An empty allowlist would block the entire web, which is a lockout rather
    # than a study session. Refuse instead of stranding you.
    # No mapfile: macOS ships bash 3.2 and it is a bash 4 builtin.
    sites=()
    while IFS= read -r line; do [ -n "$line" ] && sites+=("$line"); done \
        < <(jq -r '.studyMode.allowedSites[]? // empty' "$CONFIG" 2>/dev/null)
    [ "${#sites[@]}" -eq 0 ] && die "no allowed sites set -- add them in Settings first"

    profile="$(default_profile)"
    [ -d "$profile" ] || die "cannot find the default Firefox profile"

    # Before any state is written: if the browser will not restart, the whole
    # session is a no-op and it is better to say so than to look locked while
    # every site still loads.
    quit_firefox || die "Firefox would not quit -- nothing changed"

    mkdir -p "$STATE_DIR"
    apps="$(running_apps)"

    # Record before touching anything, so a crash midway still leaves a state
    # file that 'stop' can unwind.
    ends=$(( $(date +%s) + mins * 60 ))
    jq -n --argjson e "$ends" --arg p "$profile" --arg a "$apps" \
        '{active:true, endsAt:$e, profile:$p, apps:($a|split("\n")|map(select(length>0)))}' > "$STATE"

    # Firefox first: policies.json is only read at startup, and the session
    # files must not be moved under a running browser.
    rm -rf "$SESSION_BAK"; mkdir -p "$SESSION_BAK"
    for f in sessionstore.jsonlz4 sessionstore-backups; do
        [ -e "$profile/$f" ] && cp -R "$profile/$f" "$SESSION_BAK/" && rm -rf "$profile/$f"
    done

    [ -f "$POLICY" ] && cp "$POLICY" "$POLICY_BAK"
    mkdir -p "$POLICY_DIR"
    printf '%s\n' "${sites[@]}" | jq -R . | jq -s \
        '{policies:{WebsiteFilter:{Block:["<all_urls>"],Exceptions:.}}}' > "$POLICY"

    while IFS= read -r app; do
        [ -n "$app" ] && osascript -e "tell application \"System Events\" to set visible of process \"$app\" to false" >/dev/null 2>&1
    done <<< "$apps"

    open -a Firefox
    # The timer is a plain detached sleep. It dies with a reboot, which is the
    # documented way out.
    nohup bash -c "sleep $((mins*60)); '$0' stop done" >/dev/null 2>&1 &
    nohup "$0" guard >/dev/null 2>&1 &
    nohup "$0" watch >/dev/null 2>&1 &
    echo "study-mode: started for ${mins}m"
    ;;

stop)
    [ -f "$STATE" ] || die "not running"
    # Only the timer passes `done`; ending early earns nothing extra.
    [ "${2:-}" = done ] && bump_stats ".points += $COMPLETE_BONUS | .sessions += 1"
    profile=$(jq -r '.profile' "$STATE")
    apps=()
    while IFS= read -r line; do [ -n "$line" ] && apps+=("$line"); done \
        < <(jq -r '.apps[]?' "$STATE")

    if [ -f "$POLICY_BAK" ]; then mv "$POLICY_BAK" "$POLICY"; else rm -f "$POLICY"; fi

    quit_firefox
    for f in sessionstore.jsonlz4 sessionstore-backups; do
        [ -e "$SESSION_BAK/$f" ] && rm -rf "$profile/$f" && cp -R "$SESSION_BAK/$f" "$profile/"
    done
    rm -rf "$SESSION_BAK"
    rm -f "$STATE"

    for app in "${apps[@]}"; do
        [ -n "$app" ] && osascript -e "tell application \"System Events\" to set visible of process \"$app\" to true" >/dev/null 2>&1
    done
    open -a Firefox
    echo "study-mode: stopped"
    ;;

guard)
    # Hiding is not a lock: Cmd+Tab, a Dock click, or an app raising itself
    # brings one straight back -- which is why kitty reappeared the moment it
    # was used. Re-hide on a slow loop so "hidden" actually means out of reach
    # for the session. Quickshell is never in the list, so Settings and its End
    # button stay reachable, and the loop ends when `stop` removes the state.
    while [ -f "$STATE" ]; do
        while IFS= read -r app; do
            [ -n "$app" ] && osascript -e "tell application \"System Events\" to set visible of process \"$app\" to false" >/dev/null 2>&1
        done < <(jq -r '.apps[]?' "$STATE" 2>/dev/null)
        sleep 2
    done
    ;;

watch)
    # Once a minute: is the front app a study app, and is anyone there? A
    # focused minute earns points; an unfocused one writes a warning the bar
    # shows, and plays a sound so it lands even if the bar is not on screen.
    study_re="$KEEP_RE"
    extra=$(jq -r '.studyMode.studyApps[]? // empty' "$CONFIG" 2>/dev/null | paste -sd'|' -)
    [ -n "$extra" ] && study_re="$KEEP_RE|^($extra)\$"
    prev="$STATE_DIR/prev.png" cur="$STATE_DIR/cur.png"
    rm -f "$prev"
    while sleep 60 && [ -f "$STATE" ]; do
        front=$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null)
        idle=$(ioreg -c IOHIDSystem | awk '/HIDIdleTime/ {print int($NF/1000000000); exit}')
        moving=1
        if frame "$cur"; then
            if [ -f "$prev" ]; then
                rmse=$(magick compare -metric RMSE "$prev" "$cur" null: 2>&1 | awk -F'[()]' '{print $2}')
                awk -v r="${rmse:-1}" -v t="$STATIC_RMSE" 'BEGIN{exit !(r<t)}' && moving=0
            fi
            mv "$cur" "$prev"
        fi

        warn=""
        if [ -n "$front" ] && ! grep -qE "$study_re" <<< "$front"; then
            warn="$front isn't on your study list"
        elif [ "${idle:-0}" -ge "$IDLE_LIMIT" ] && [ "$moving" = 0 ]; then
            warn="No activity for $((idle / 60)) min -- still studying?"
        fi

        if [ -z "$warn" ]; then
            bump_stats ".points += $POINTS_PER_MIN | .days[\"$(date +%F)\"] += 1"
        else
            bump_stats '.warnings += 1'
            jq --arg w "$warn" --argjson at "$(date +%s)" '.warn = {text:$w, at:$at}' "$STATE" > "$STATE.tmp" \
                && mv "$STATE.tmp" "$STATE"
            afplay /System/Library/Sounds/Funk.aiff >/dev/null 2>&1 &
        fi
    done
    rm -f "$prev" "$cur"
    ;;

status)
    stats=$(cat "$STATS" 2>/dev/null || echo '{}')
    if [ -f "$STATE" ]; then
        jq --argjson now "$(date +%s)" --argjson s "$stats" \
            '{active:true, endsAt:.endsAt, remaining:(.endsAt-$now), warn:(.warn // null), stats:$s}' "$STATE"
    else
        jq -n --argjson s "$stats" '{active:false, remaining:0, stats:$s}'
    fi
    ;;
*) die "usage: study-mode.sh start [minutes] | stop | status" ;;
esac
