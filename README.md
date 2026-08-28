# darwin-dotfiles

macOS desktop config: yabai + skhd for tiling, JankyBorders, a
[SketchyBar](https://github.com/minimal-05/sketchybar) bar, and
[Quickshell running natively on macOS](https://github.com/minimal-05/quickshell-macos).

## Install

```sh
git clone https://github.com/minimal-05/darwin-dotfiles.git ~/.config-new
# ~/.config usually exists already — merge rather than clobber:
rsync -a ~/.config-new/ ~/.config/ && rm -rf ~/.config-new
~/.config/install.sh
```

Idempotent — re-run after pulling. `--no-deps` skips Homebrew.

## Layout

```
quickshell/     the bar I actually run — pills, services, workspace dots
yabai/ skhd/    tiling WM and hotkeys
karabiner/      media-key grabs, routed to quickshell over IPC
borders/        active-window border
kitty/ nvim/    terminal and editor
btop/ nnn/ starship.toml
firefox-autoconfig/
```

Two directories are separate repos, cloned by `install.sh`:

- **`sketchybar/`** → [minimal-05/sketchybar](https://github.com/minimal-05/sketchybar)
- **`~/Projects/quickshell-macos`** → [minimal-05/quickshell-macos](https://github.com/minimal-05/quickshell-macos)

## Notes

- The media keys are grabbed by **Karabiner** at the HID level and forwarded to
  Quickshell over IPC. macOS never sees the keypress, so it never draws its own
  volume/brightness HUD — that is the whole mechanism behind the custom OSD.
  Karabiner can't match brightness key codes in a `from` clause (they're
  output-only), so the rules match plain `f1`–`f12`.
- `karabiner.json` and `skhdrc` use **absolute paths** to `qs-ipc`; `install.sh`
  rewrites them for your home directory.
- yabai's scripting addition needs SIP partially disabled.
