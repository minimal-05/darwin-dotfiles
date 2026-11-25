# Everything install.sh takes from Homebrew. Project tooling is left out on purpose.
cask_args adopt: true # take over apps that were installed by hand

# window management
brew "asmvik/formulae/yabai", trusted: true
brew "felixkratz/formulae/borders", trusted: true
cask "jackielii/tap/skhd-zig", trusted: true # a cask now, not a formula
cask "karabiner-elements"
cask "homerow"

# quickshell: build (cli11 is the one its own install.sh does not list), then what it shells out to
brew "qt"
brew "cmake"
brew "ninja"
brew "pkgconf"
brew "cli11"
brew "python"
brew "jq"
brew "media-control"
brew "blueutil"
brew "switchaudio-osx"
brew "brightness"
brew "imagemagick"
brew "ffmpeg"
brew "tesseract"
brew "exiftool"
brew "smudge/smudge/nightlight", trusted: true

# terminal and editors
cask "kitty"
cask "vscodium"
brew "neovim"
brew "lua"
brew "starship"
brew "zoxide"
brew "zsh-autosuggestions"
brew "fzf"
brew "ripgrep"
brew "fd"
brew "nnn"
brew "btop"
brew "fastfetch"
brew "lazygit"
brew "gh"
brew "pyenv"
brew "rbenv"

# fonts
cask "font-comic-shanns-mono-nerd-font"
cask "font-maple-mono-nf"
cask "font-symbols-only-nerd-font"
cask "font-material-symbols"
cask "font-roboto-flex"

# apps
cask "firefox"
cask "google-chrome"
cask "claude"
cask "prusaslicer"
cask "autodesk-fusion"

# App Store. Sign in to it first, or these are skipped. Xcode is not here: the
# current one needs a newer macOS, and only the App Store's own window offers
# the last version that runs on this one.
mas "Exam.net", id: 1496582158
mas "Bluebook Exams", id: 1645016851
