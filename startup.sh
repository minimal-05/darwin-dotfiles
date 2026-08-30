#!/bin/sh
# Bring the desktop up, and make it come back at every login. Safe to re-run.
#
# Everything here is a launchd agent, so this is really just "install and load
# the agents" -- after the first run, logging in does it.
#
#   yabai      com.koekeishiya.yabai      (yabai --start-service)
#   skhd       com.jackielii.skhd         (skhd --start-service)
#   borders    homebrew.mxcl.borders      (brew services)
#   Files.app  org.quickshell.files       (written by qs-make-app)
#   the bar    org.quickshell.bar         (written below)
#
# Plus `yabai --load-sa`, which is the one step launchd cannot do for you: it
# needs root, and a login agent has no terminal to ask for a password on.
#
# Karabiner installs its own org.pqrs.* agents when you install the app.
# SketchyBar is deliberately absent: it is the *other* bar, and only one of the
# two may run at a time -- see qs-switch.
set -eu

QS="$HOME/Projects/quickshell-macos"
AGENTS="$HOME/Library/LaunchAgents"
BAR="$AGENTS/org.quickshell.bar.plist"
GUI="gui/$(id -u)"

say() { printf '\033[1;34m==>\033[0m %s\n' "$1"; }

# These exit non-zero when the thing is already up, which is not an error here.
ok() { "$@" >/dev/null 2>&1 || true; }

mkdir -p "$AGENTS"

say "yabai scripting addition"
# Needs SIP partially disabled (csrutil status) and root. /etc/sudoers.d/yabai
# carries a NOPASSWD rule so this never prompts -- but the rule pins the yabai
# binary's sha256, so a `brew upgrade yabai` silently invalidates it, and yours
# is currently an empty file. Either way the recovery is the same, so just do
# it: fix-sa-sudoers.sh rewrites the rule and reloads. It needs your password
# that once, and nothing here asks again until the next yabai upgrade.
#
# Loaded before yabai starts, so a cold start comes up with it already in place.
if sudo -n yabai --load-sa 2>/dev/null; then
    echo "  loaded"
elif [ -t 0 ]; then
    echo "  no usable NOPASSWD rule -- rebuilding it (asks for your password once)"
    "$HOME/.config/yabai/fix-sa-sudoers.sh" \
        || echo "  FAILED: check that 'csrutil status' says disabled"
else
    # Never prompt with no terminal to prompt on: run from launchd or a hotkey
    # this would hang forever holding the rest of the desktop hostage.
    echo "  skipped: needs a password once, and there is no terminal to ask on"
    echo "  run this script from a terminal to finish the setup"
fi

say "yabai"
ok yabai --start-service
say "skhd"
# skhd --install-service bakes the *versioned* Cellar path into its plist, so a
# `brew upgrade skhd-zig` silently leaves an agent pointing at a binary that is
# gone. Rewrite it when it no longer matches the skhd on PATH.
SKHD_PLIST="$AGENTS/com.jackielii.skhd.plist"
grep -qF "$(readlink -f "$(command -v skhd)")" "$SKHD_PLIST" 2>/dev/null || {
    ok skhd --uninstall-service
    ok skhd --install-service
}
ok skhd --start-service
say "borders"; ok brew services start borders

# The hidden warm-start of finder.qml. qs-make-app writes its own agent and
# restarts the running process, so only call it when it has not been set up.
say "Files.app"
[ -f "$AGENTS/org.quickshell.files.plist" ] || "$QS/bin/qs-make-app"

say "bar"
cat > "$BAR" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>org.quickshell.bar</string>
    <key>ProgramArguments</key>
    <array>
        <string>$QS/bin/qs-start</string>
    </array>
    <!-- No -p: configs are directories under ~/.config/quickshell and the
         binary defaults QS_CONFIG_NAME to \`end4\` (src/launch/tools.cpp), so
         naming a path here would only be a second place to update. Run a
         different one with \`qs -c mine\`.

         qs-start execs quickshell, so this job's lifetime is the real process
         rather than a launcher that returns immediately.

         KeepAlive because the shell exits on its own: quickshell quits when the
         config tree it is rooted in changes, and ~/.config is a git repo, so an
         ordinary commit or checkout takes the bar down with exit code 0 and it
         stays down. That is exactly what the old note here predicted. It used to
         be omitted so `qs-switch sketchybar` could kill the bar without launchd
         fighting it; qs-switch is gone and there is no second bar, so nothing
         wants it dead any more.

         qs-dev restarts the shell in place and is the one thing that does kill
         it deliberately -- it pkills and relaunches, so launchd bringing the old
         one back is not a race it can lose. -->
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>ThrottleInterval</key><integer>5</integer>
    <key>ProcessType</key><string>Interactive</string>
    <key>StandardOutPath</key><string>/tmp/quickshell-bar.log</string>
    <key>StandardErrorPath</key><string>/tmp/quickshell-bar.log</string>
</dict>
</plist>
PLIST

# bootout is asynchronous: it returns before launchd has finished reaping the
# job, and bootstrapping into a domain that still holds the old label fails with
# a bare "Input/output error". So wait for the label to actually leave.
# ponytail: a poll, because launchctl offers nothing to wait on.
if launchctl print "$GUI/org.quickshell.bar" >/dev/null 2>&1; then
    ok launchctl bootout "$GUI/org.quickshell.bar"
    n=0
    while launchctl print "$GUI/org.quickshell.bar" >/dev/null 2>&1 && [ "$n" -lt 50 ]; do
        n=$((n + 1))
        sleep 0.1
    done
fi
launchctl bootstrap "$GUI" "$BAR"

echo
say "Loaded"
launchctl list | grep -E 'yabai|skhd|quickshell|borders|sketchybar' || true
