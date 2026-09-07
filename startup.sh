#!/bin/sh
# Bring the desktop up, and make it come back at every login. Safe to re-run.
#
# Everything here is a launchd agent, so this is really just "install and load
# the agents" -- after the first run, logging in does it.
#
#   yabai      com.koekeishiya.yabai      (yabai --start-service)
#   skhd       local.skhd                 (written below)
#   borders    homebrew.mxcl.borders      (brew services)
#   Files.app  org.quickshell.files       (written by qs-make-app)
#   Settings.app                          (written by qs-make-app, no agent)
#   the bar    org.quickshell.bar         (written below)
#
# Plus `yabai --load-sa`, which is the one step launchd cannot do for you: it
# needs root, and a login agent has no terminal to ask for a password on.
#
# Karabiner installs its own org.pqrs.* agents when you install the app.
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
# Needs SIP partially disabled and root. /etc/sudoers.d/yabai carries a
# NOPASSWD rule pinned to the yabai binary's sha256, so a `brew upgrade yabai`
# silently invalidates it; fix-sa-sudoers.sh rewrites the rule, asking for a
# password once -- which only a terminal can answer, never launchd or a hotkey.
sudo -n yabai --load-sa 2>/dev/null || { [ -t 0 ] && "$HOME/.config/yabai/fix-sa-sudoers.sh"; } || echo "load-sa: run once from a terminal"

say "yabai"
ok yabai --start-service
say "skhd"
# skhd-zig is a cask now: /Applications/skhd.app, registering its agent through
# SMAppService. That registration does not work here -- `launchctl print` reports
# runs = 0 and job state = uninitialized however many times it is reinstalled or
# approved, so launchd never starts it and every binding is dead.
#
# A plain LaunchAgent onto the same binary does run. Distinct label so it cannot
# collide with the cask's com.jackielii.skhd: if that one ever starts working,
# bootout this one, or the two double-fire every binding.
SKHD_BIN="/Applications/skhd.app/Contents/MacOS/skhd"
SKHD_PLIST="$AGENTS/local.skhd.plist"
if [ -x "$SKHD_BIN" ]; then
    cat > "$SKHD_PLIST" <<SKHDPLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>local.skhd</string>
    <key>ProgramArguments</key>
    <array><string>$SKHD_BIN</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>ThrottleInterval</key><integer>5</integer>
    <key>ProcessType</key><string>Interactive</string>
    <key>StandardOutPath</key><string>/tmp/skhd.log</string>
    <key>StandardErrorPath</key><string>/tmp/skhd.log</string>
</dict>
</plist>
SKHDPLIST
    ok launchctl bootout "$GUI/local.skhd"
    ok launchctl bootstrap "$GUI" "$SKHD_PLIST"
else
    echo "  skhd not installed at $SKHD_BIN -- run install.sh"
fi
say "borders"; ok brew services start borders

# The Spotlight- and dock-launchable wrappers around finder.qml and settings.qml,
# plus the hidden warm-start of finder.qml. qs-make-app writes Files' agent and
# restarts the running process, so only call it when one of the two is missing.
say "Files.app, Settings.app"
if [ ! -f "$AGENTS/org.quickshell.files.plist" ] || [ ! -d "$HOME/Applications/Settings.app" ]; then
    "$QS/bin/qs-make-app"
fi

say "bar"
# No -p: the binary defaults QS_CONFIG_NAME to end4 (src/launch/tools.cpp). KeepAlive
# because quickshell quits when its config tree changes -- a git checkout here takes
# the bar down with exit 0 -- though this machine does not honour it yet. qs-dev pkills on purpose.
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

# bootstrap alone is not enough here: launchd registers the job but does not
# honour RunAtLoad, so everything sits at runs = 0 until it is kicked. The same
# machine also ignores KeepAlive -- killing an agent does not bring it back,
# which is true even of homebrew's own borders agent, so it is not something
# these plists are doing wrong. Kick each one and check it took.
say "Starting"
for label in local.skhd org.quickshell.files org.quickshell.bar; do
    launchctl print "$GUI/$label" >/dev/null 2>&1 || continue
    ok launchctl kickstart "$GUI/$label"
done
sleep 3

echo
say "Loaded"
launchctl list | grep -E 'yabai|borders|skhd|quickshell'
