#!/usr/bin/env bash
# Smart Firefox launcher (bound to ctrl+alt+cmd - g in skhd).
#   neither profile open -> open BOTH
#   one profile open     -> open the MISSING one
#   both profiles open   -> new window on default-release
# No debug servers: nothing here enables remote debugging, so Firefox never
# shows the "under remote control" (red) indicator.
# MOZ_DISABLE_SAFE_MODE_KEY stops the Option-in-hotkey Troubleshoot Mode trigger.

FF="/Applications/Firefox.app/Contents/MacOS/firefox"
export MOZ_DISABLE_SAFE_MODE_KEY=1

running="$(ps -axo command= | grep -E '/MacOS/firefox( |$)' | grep -v plugin-container)"
dr=false; d=false
grep -Eq -- '-P default-release' <<<"$running" && dr=true
grep -Eq -- '-P default( |$)'    <<<"$running" && d=true

# default is --no-remote so it runs as its own instance alongside default-release,
# which keeps Firefox's remoting (so bare --new-window lands on default-release).
open_dr() { "$FF" --single-instance -P default-release >/dev/null 2>&1 & }
open_d()  { "$FF" --no-remote       -P default         >/dev/null 2>&1 & }

if ! $dr && ! $d; then
    open_d           # bring up default first (it opts out of remoting)...
    sleep 2          # ...give it a moment...
    open_dr          # ...then default-release claims remoting cleanly
elif $dr && ! $d; then
    open_d           # default-release already up -> open the missing default
elif ! $dr && $d; then
    open_dr          # default already up -> open the missing default-release
else
    # both up: a profile can't run as two processes, so open a new window in
    # the running default-release (it owns remoting; default is --no-remote).
    "$FF" --new-window >/dev/null 2>&1 &
fi
