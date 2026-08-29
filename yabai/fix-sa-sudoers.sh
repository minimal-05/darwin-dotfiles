#!/usr/bin/env bash
# Re-write the NOPASSWD rule for `yabai --load-sa` and load the scripting addition.
# Re-run this after every yabai upgrade: the rule pins the binary's sha256.
set -euo pipefail

BIN=$(command -v yabai)
LINE="$(whoami) ALL=(root) NOPASSWD: sha256:$(shasum -a 256 "$BIN" | cut -d' ' -f1) $BIN --load-sa"
TMP=$(mktemp)
printf '%s\n' "$LINE" > "$TMP"

sudo visudo -c -f "$TMP"                    # refuse to install a broken sudoers file
sudo install -m 0440 -o root -g wheel "$TMP" /etc/sudoers.d/yabai
rm -f "$TMP"

sudo yabai --load-sa || { sudo yabai --install-sa && sudo yabai --load-sa; }
yabai --restart-service
sleep 2
yabai -m space --focus 1 && echo "OK: space focus works"
