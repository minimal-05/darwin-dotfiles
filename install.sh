#!/usr/bin/env bash
# Set this desktop up on a Mac, from nothing to a running bar. Safe to re-run.
#
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/minimal-05/darwin-dotfiles/main/install.sh)"
#
#   ~/.config/install.sh              the same, from a checkout
#   ~/.config/install.sh --no-deps    skip Homebrew; just build, retarget and load
#
# Homebrew, this repo into ~/.config, packages, the quickshell fork (cloned and
# built), home files and settings, the agents (startup.sh), and then a list of
# the grants macOS will not let a script give itself. That list is not optional:
# without it the hotkey daemon exits on launch and the shell renders no previews.
set -euo pipefail

REPO="${DOTFILES_REPO:-https://github.com/minimal-05/darwin-dotfiles.git}"
DOTS="$HOME/.config"
QS_DIR="$HOME/Projects/quickshell-macos"
STAMP="$(date +%Y%m%d-%H%M%S)"

say()  { printf '\n\033[1;34m==>\033[0m %s\n' "$1"; }
warn() { printf '\033[33m    %s\033[0m\n' "$1"; }
die()  { printf '\033[31m%s\033[0m\n' "$1" >&2; exit 1; }

[ "$(uname -sm)" = "Darwin arm64" ] || die "Apple silicon Macs only."

if ! command -v brew >/dev/null && [ ! -x /opt/homebrew/bin/brew ]; then
  say "Homebrew (asks for your password; also installs git)"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
command -v brew >/dev/null || eval "$(/opt/homebrew/bin/brew shellenv)"

# Not running from a checkout (curl, or a stray copy): put one in ~/.config and
# carry on from there. Anything of yours it would overwrite is moved aside first.
if [ ! "${BASH_SOURCE[0]:-/}" -ef "$DOTS/install.sh" ] || [ ! -e "$DOTS/.git" ]; then
  say "Dotfiles into $DOTS"
  if [ -e "$DOTS/.git" ]; then
    case "$(git -C "$DOTS" remote get-url origin 2>/dev/null || true)" in
      "$REPO"|*minimal-05/darwin-dotfiles*) ;;
      *) die "$DOTS is already a git repo for something else. Move it aside and re-run." ;;
    esac
    git -C "$DOTS" pull --ff-only --quiet || warn "could not fast-forward $DOTS; using it as it is"
  else
    TMP="$(mktemp -d)"
    git clone --quiet "$REPO" "$TMP/dots"
    BACKUP="$HOME/.config-backup-$STAMP"
    while IFS= read -r -d '' f; do
      [ -e "$DOTS/$f" ] || [ -L "$DOTS/$f" ] || continue
      cmp -s "$TMP/dots/$f" "$DOTS/$f" && continue
      mkdir -p "$BACKUP/$(dirname "$f")"
      mv "$DOTS/$f" "$BACKUP/$f"
    done < <(git -C "$TMP/dots" ls-files -z)
    mkdir -p "$DOTS"
    mv "$TMP/dots/.git" "$DOTS/.git"
    git -C "$DOTS" checkout --quiet -- .
    rm -rf "$TMP"
    [ ! -d "$BACKUP" ] || warn "files that were in the way: $BACKUP"
  fi
  exec "$DOTS/install.sh" "$@"
fi
cd "$DOTS"

if [ "${1:-}" != "--no-deps" ]; then
  say "Packages and apps"
  # One bad entry (an App Store app, signed out) must not cost the whole desktop.
  brew bundle install --file="$DOTS/Brewfile" || warn "some packages failed (listed above); re-run later"
  # The colour scripts' Python side.
  "$(brew --prefix)/bin/python3" -m pip install --quiet --user --break-system-packages \
    materialyoucolor numpy pillow opencv-python-headless || warn "Python packages failed; wallpaper colours will not generate"
fi

say "Quickshell (macOS fork)"
if [ -d "$QS_DIR/.git" ]; then
  git -C "$QS_DIR" pull --ff-only --quiet || warn "could not fast-forward $QS_DIR; leaving it alone"
else
  mkdir -p "$(dirname "$QS_DIR")"
  git clone --quiet https://github.com/minimal-05/quickshell-macos.git "$QS_DIR"
fi
# Builds Quickshell.app, installs every tool into it, and writes ~/.local/bin/qs.
"$QS_DIR/install.sh" || warn "quickshell did not build; the bar will not start until it does"

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

say "Home files"
# place <file in home/> <destination>: linked, so edits land in the repo.
place() {
  [ "$(readlink "$2" || true)" != "$DOTS/home/$1" ] || return 0
  if [ -e "$2" ]; then mv "$2" "$2.before-dotfiles-$STAMP"; warn "kept your old one: $2.before-dotfiles-$STAMP"; fi
  ln -sfn "$DOTS/home/$1" "$2"
  echo "  $2"
}
place .zshrc "$HOME/.zshrc"
place .zprofile "$HOME/.zprofile"
# seed <file in home/> <destination>: copied once; the app owns it afterwards.
seed() {
  [ ! -e "$2" ] || return 0
  mkdir -p "$(dirname "$2")"
  sed "s#@HOME@#$HOME#g" "$DOTS/home/$1" > "$2"
  echo "  $2"
}
seed illogical-impulse.json "$HOME/Library/Preferences/illogical-impulse/config.json"
seed vscodium-settings.json "$HOME/Library/Application Support/VSCodium/User/settings.json"

say "macOS, Homerow and Firefox settings"
"$DOTS/macos.sh" || warn "some settings did not apply"
if [ -d /Applications/Firefox.app ]; then
  "$DOTS/firefox-autoconfig/install.sh" || warn "grant your terminal App Management, then run firefox-autoconfig/install.sh"
fi

say "Agents"
"$DOTS/startup.sh" || warn "not everything loaded; run ~/.config/startup.sh after step 3 below"

cat <<EOF

$(printf '\033[1;32mDone.\033[0m')

  Dotfiles     $DOTS
  Quickshell   $QS_DIR              (own repo)
  Command      ~/.local/bin/qs

Things macOS will not let this script do. Until 1-3 are done, skhd exits on
launch and the shell shows no window previews:

  1. System Settings > Privacy & Security > Accessibility
       enable skhd, yabai, Homerow and Quickshell, then: ~/.config/startup.sh

  2. System Settings > Privacy & Security > Screen & System Audio Recording
       enable Quickshell  (window thumbnails, the overview, screenshots)

  3. System Settings > General > Login Items & Extensions
       allow qs-start, skhd, yabai and open in the background. Then open
       Karabiner-Elements once; it walks you through its driver extension.

  4. yabai's scripting addition (moving windows between Spaces) needs SIP off:
     https://github.com/asmvik/yabai/wiki -- then run ~/.config/startup.sh again.
     Everything else works without it.

  5. App Store: sign in, then re-run this for Exam.net and Bluebook, and get
     Xcode from its page there (it offers the last version this macOS can run).

  6. gh auth login && gh auth setup-git
     git config --global user.name  <name>
     git config --global user.email <email>
EOF
