#!/usr/bin/env bash
# Set this dotfiles checkout up on a Mac. Safe to re-run.
#
#   ./install.sh            everything
#   ./install.sh --no-deps  skip Homebrew, just link/clone/patch paths
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
DOTS="$(pwd)"
QS_DIR="$HOME/Projects/quickshell-macos"

say() { printf '\n\033[1;34m==>\033[0m %s\n' "$1"; }

[ "$(uname -s)" = "Darwin" ] || { echo "macOS only." >&2; exit 1; }
[ "$DOTS" = "$HOME/.config" ] || echo "warning: expected ~/.config, running from $DOTS"

if [ "${1:-}" != "--no-deps" ]; then
  command -v brew >/dev/null || { echo "Install Homebrew first: https://brew.sh" >&2; exit 1; }

  say "Taps"
  brew tap koekeishiya/formulae
  brew tap felixkratz/formulae
  brew tap jackielii/tap

  say "Window management"
  # skhd-zig, not koekeishiya/skhd — it provides the same `skhd` binary.
  brew install --quiet koekeishiya/formulae/yabai jackielii/tap/skhd-zig felixkratz/formulae/borders

  say "Shell and CLI"
  brew install --quiet starship fzf ripgrep fd lazygit btop nnn neovim lua jq

  say "Casks"
  brew install --quiet --cask kitty karabiner-elements
fi

say "SketchyBar"
# Its own repo — see the note in .gitignore.
if [ -d sketchybar/.git ]; then
  git -C sketchybar pull --ff-only --quiet || true
else
  rm -rf sketchybar
  git clone --quiet https://github.com/minimal-05/sketchybar.git sketchybar
fi
./sketchybar/install.sh

say "Quickshell (macOS fork)"
if [ -d "$QS_DIR/.git" ]; then
  git -C "$QS_DIR" pull --ff-only --quiet || true
else
  mkdir -p "$(dirname "$QS_DIR")"
  git clone --quiet https://github.com/minimal-05/quickshell-macos.git "$QS_DIR"
fi
"$QS_DIR/install.sh"

# karabiner.json and skhdrc call qs-ipc by absolute path — Karabiner does not
# expand ~. Retarget them at whoever is installing.
say "Retargeting absolute paths"
for f in karabiner/karabiner.json skhd/skhdrc; do
  [ -f "$f" ] || continue
  if sed -i '' -E "s#/Users/[^/\"' ]+/Projects/quickshell-macos#$QS_DIR#g" "$f"; then
    echo "  $f"
  fi
done

say "Services"
yabai --start-service   || true
skhd --start-service    || true
brew services start borders || true

cat <<EOF

Done.

  Dotfiles     $DOTS
  SketchyBar   $DOTS/sketchybar        (own repo)
  Quickshell   $QS_DIR                 (own repo)

  Start the bar:  $QS_DIR/bin/qs-switch mine

  yabai's scripting addition needs SIP partially disabled and a manual
  'sudo yabai --load-sa' — see https://github.com/koekeishiya/yabai/wiki
EOF
