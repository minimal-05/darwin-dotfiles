#!/usr/bin/env bash
# Re-run after every yabai upgrade: the NOPASSWD rule pins the binary's sha256.
echo "$(whoami) ALL=(root) NOPASSWD: sha256:$(shasum -a 256 "$(which yabai)" | cut -d' ' -f1) $(which yabai) --load-sa" | sudo tee /etc/sudoers.d/yabai
sudo yabai --load-sa && yabai --restart-service
