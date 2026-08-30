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
quickshell/     shell configs, one dir each — `qs -c end4`, `qs -c mine`
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

- **Never put a `shell.qml` at the top of `~/.config/quickshell`.** Quickshell
  registers `<xdg dir>/quickshell/shell.qml` as the `default` config and then
  ignores every subdirectory — one stray file makes `end4` and `mine` both
  invisible, with no error at all. Configs are directories: `qs -c end4`.
- Scripts name the config directory **in full** (`$HOME/.config/quickshell/end4`),
  never a relative walk up from their own location — a relative walk is what
  silently broke `switchwall.sh` the last time this tree moved.
- `karabiner/karabiner.json` and `skhd/skhdrc` call `qs-ipc` by **absolute path**
  because Karabiner does not expand `~`. `install.sh` rewrites them; keep it so.
- Generated files are tracked (`kitty/theme.conf` and friends). The colour
  scripts overwrite them on every wallpaper change.

- The media keys are grabbed by **Karabiner** at the HID level and forwarded to
  Quickshell over IPC. macOS never sees the keypress, so it never draws its own
  volume/brightness HUD — that is the whole mechanism behind the custom OSD.
  Karabiner can't match brightness key codes in a `from` clause (they're
  output-only), so the rules match plain `f1`–`f12`.
- `karabiner.json` and `skhdrc` use **absolute paths** to `qs-ipc`; `install.sh`
  rewrites them for your home directory.
- yabai's scripting addition needs SIP partially disabled.
