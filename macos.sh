#!/bin/sh
# macOS and Homerow settings this desktop expects. Safe to re-run.
set -eu
cd "$(dirname "$0")"
G=NSGlobalDomain

defaults write $G KeyRepeat -int 1
defaults write $G InitialKeyRepeat -int 15
defaults write $G AppleInterfaceStyle -string Dark
defaults write $G _HIHideMenuBar -bool true # the bar draws there
defaults write $G AppleShowAllExtensions -bool true
defaults write $G NSAutomaticSpellingCorrectionEnabled -bool false
defaults write $G NSAutomaticCapitalizationEnabled -bool false
defaults write $G NSAutomaticPeriodSubstitutionEnabled -bool false
defaults write $G NSAutomaticQuoteSubstitutionEnabled -bool false
defaults write $G NSAutomaticWindowAnimationsEnabled -bool false
defaults write $G com.apple.mouse.scaling -float 0.875

defaults write com.apple.dock autohide -bool true
defaults write com.apple.dock autohide-delay -float 1000 # i.e. never: the shell has its own dock
defaults write com.apple.dock mru-spaces -bool false     # yabai addresses Spaces by index
defaults write com.apple.dock show-recents -bool false
defaults write com.apple.dock expose-group-apps -bool false
defaults write com.apple.spaces spans-displays -bool false
defaults write com.apple.WindowManager EnableStandardClickToShowDesktop -bool false
defaults write com.apple.WindowManager GloballyEnabled -bool false

defaults write com.apple.finder AppleShowAllFiles -bool true
defaults write com.apple.finder FXPreferredViewStyle -string icnv
mkdir -p "$HOME/Pictures/Screenshots"
defaults write com.apple.screencapture location -string "$HOME/Pictures/Screenshots"
defaults write com.apple.screencapture disable-shadow -bool true
defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true

# The system shortcuts switched off so skhd, Karabiner and the shell can have them.
defaults import com.apple.symbolichotkeys home/symbolichotkeys.plist

# Homerow: ctrl+alt+cmd+R, no scroll or search shortcut
H=com.superultra.Homerow
NONE='{"carbonKeyCode":-1,"carbonModifiers":0,"mouseButtonNumbers":[],"modifierKeyCodes":[]}'
defaults write $H KeyboardShortcuts_clickMode -string '{"carbonKeyCode":15,"carbonModifiers":6400,"mouseButtonNumbers":[],"modifierKeyCodes":[]}'
defaults write $H KeyboardShortcuts_scrollMode -string "$NONE"
defaults write $H KeyboardShortcuts_searchMode -string "$NONE"
defaults write $H non-search-shortcut -string '⌃⌥⌘R'
defaults write $H scroll-shortcut -string ''
defaults write $H search-shortcut -string ''
defaults write $H auto-switch-input-source-id -string com.apple.keylayout.ABC
defaults write $H shortcuts-migrated-v1 -bool true
defaults write $H enable-hyper-key -bool false
defaults write $H launch-at-login -bool true

/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u 2>/dev/null || true
killall Dock Finder 2>/dev/null || true
