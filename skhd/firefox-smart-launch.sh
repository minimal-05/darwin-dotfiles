#!/usr/bin/env bash
# Smart Firefox launcher (ctrl+alt+cmd - g in skhd): opens whichever of the two
# profiles is not running, or a new window when both are. Nothing here enables
# remote debugging, so Firefox never shows the "under remote control" indicator.
FF="/Applications/Firefox.app/Contents/MacOS/firefox"
export MOZ_DISABLE_SAFE_MODE_KEY=1   # no Option-in-hotkey Troubleshoot Mode
pgrep -qf -- '/MacOS/firefox .*-P default-release' && dr=true || dr=false
pgrep -qf -- '/MacOS/firefox .*-P default( |$)'    && d=true  || d=false
# default is --no-remote so it runs as its own instance alongside default-release,
# which keeps Firefox's remoting (so bare --new-window lands on default-release).
open_dr() { "$FF" --single-instance -P default-release >/dev/null 2>&1 & }
open_d()  { "$FF" --no-remote       -P default         >/dev/null 2>&1 & }
$d || open_d
$dr || { $d || sleep 2; open_dr; }   # default first: it opts out of remoting
$d && $dr && "$FF" --new-window >/dev/null 2>&1 &
