#!/usr/bin/env bash
# Set this desktop up on a Mac, from nothing to a running bar. Safe to re-run.
#
#   ./install.sh              everything
#   ./install.sh --no-deps    skip Homebrew; just build, retarget and load
#
# Four stages: packages, the quickshell fork (cloned and built), the agents
# (startup.sh), and then a list of the grants macOS will not let a script give
# itself. The last stage is not optional -- without those grants the hotkey
# daemon exits on launch and the shell renders no window previews.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
DOTS="$(pwd)"
QS_DIR="$HOME/Projects/quickshell-macos"

say()  { printf '\n\033[1;34m==>\033[0m %s\n' "$1"; }
warn() { printf '\033[33m    %s\033[0m\n' "$1"; }

[ "$(uname -s)" = "Darwin" ] || { echo "macOS only." >&2; exit 1; }
[ "$DOTS" = "$HOME/.config" ] || warn "expected ~/.config, running from $DOTS"

if [ "${1:-}" != "--no-deps" ]; then
  command -v brew >/dev/null || { echo "Install Homebrew first: https://brew.sh" >&2; exit 1; }

  say "Taps"
  brew tap koekeishiya/formulae
  brew tap felixkratz/formulae
  brew tap jackielii/tap

  say "Window management"
  brew install --quiet koekeishiya/formulae/yabai felixkratz/formulae/borders
  # skhd-zig is a *cask* now (/Applications/skhd.app), not a formula. It used to
  # be one; installing it as a formula fails outright on a clean machine.
  brew install --quiet --cask jackielii/tap/skhd-zig

  say "Shell and CLI"
  brew install --quiet starship fzf ripgrep fd lazygit btop nnn neovim lua jq

  say "Casks"
  brew install --quiet --cask kitty karabiner-elements
fi

say "Quickshell (macOS fork)"
if [ -d "$QS_DIR/.git" ]; then
  git -C "$QS_DIR" pull --ff-only --quiet || warn "could not fast-forward $QS_DIR; leaving it alone"
else
  mkdir -p "$(dirname "$QS_DIR")"
  git clone --quiet https://github.com/minimal-05/quickshell-macos.git "$QS_DIR"
fi
# Builds Quickshell.app, installs every tool into it, and writes ~/.local/bin/qs.
"$QS_DIR/install.sh"

# karabiner.json and skhdrc call qs-ipc by absolute path -- Karabiner does not
# expand ~. Retarget them at whoever is installing.
say "Retargeting absolute paths"
for f in karabiner/karabiner.json skhd/skhdrc; do
  [ -f "$f" ] || continue
  sed -i '' -E "s#/Users/[^/\"' ]+/Projects/quickshell-macos#$QS_DIR#g" "$f" && echo "  $f"
done

say "Shell configs"
# A shell.qml at the TOP of ~/.config/quickshell registers as the `default`
# config, and quickshell then ignores every subdirectory -- both named configs
# become invisible, with no error. Worth failing loudly on, because the symptom
# is "my config vanished" rather than anything pointing here.
if [ -f "$HOME/.config/quickshell/shell.qml" ]; then
  warn "~/.config/quickshell/shell.qml exists. It shadows every named config."
  warn "Move it into a directory of its own before running the shell."
fi
for c in "$HOME"/.config/quickshell/*/; do
  [ -f "$c/shell.qml" ] && echo "  $(basename "$c")  ->  qs -c $(basename "$c")"
done

say "Agents"
"$DOTS/startup.sh"

cat <<EOF

$(printf '\033[1;32mDone.\033[0m')

  Dotfiles     $DOTS
  Quickshell   $QS_DIR              (own repo)
  Command      ~/.local/bin/qs

Three things macOS will not let this script do. Until they are granted, skhd
exits on launch and the shell shows no window previews:

  1. System Settings > Privacy & Security > Accessibility
       add /Applications/skhd.app, then: skhd --restart-service

  2. System Settings > Privacy & Security > Screen & System Audio Recording
       enable Quickshell  (window thumbnails, the overview, screenshots)

  3. System Settings > General > Login Items & Extensions > Allow in the
     Background -- enable qs-start, skhd, yabai and open, or nothing starts
     itself at login.

  yabai's scripting addition also needs SIP partially disabled and one
  'sudo yabai --load-sa' -- see https://github.com/koekeishiya/yabai/wiki
EOF
