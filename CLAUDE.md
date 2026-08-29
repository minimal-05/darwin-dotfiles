# darwin-dotfiles — where things live

This repo (`~/.config`) is the **canonical home for live config**. If a config
file is loaded by a running program, it lives here — with one exception below,
which is its own repo because it carries a build step of its own.

## Two repos, not one

| Path | Repo | Holds |
|---|---|---|
| `~/.config` | `darwin-dotfiles` | everything here — yabai, skhd, karabiner, kitty, nvim, borders, btop, nnn, starship, **and the quickshell shell config** |
| `~/Projects/quickshell-macos` | `quickshell-macos` | the C++ Cocoa fork **and** its `bin/qs-*` launchers |

`./install.sh` clones it and wires it up.

## The quickshell split — read before editing any .qml

- **Shell configs** → `~/.config/quickshell/<name>` (here, in this repo).
- **The binary, launchers, shims** → `~/Projects/quickshell-macos`.

The binary and the config are separate on purpose: `qs` is one installed
application, and a config is a directory it is pointed at. There are two:

| | |
|---|---|
| `quickshell/end4` | end-4's illogical-impulse, adapted for macOS — third party, its own licence, ~950 files. `qs -c end4` |
| `quickshell/mine` | a small self-contained bar of our own, one file, no shared code with end4. `qs -c mine` |

**Never put a `shell.qml` at the top of `~/.config/quickshell`.** Quickshell
registers `<xdg dir>/quickshell/shell.qml` as the `default` config and then
*ignores every subdirectory* — one top-level file is all it takes to make both
named configs invisible. That is why the tree was nested on 2026-08-29; before
that there was exactly one config and no way to run a second.

They are tracked here rather than left loose because they are live config that
gets edited constantly, and end4 spent long enough untracked under
`quickshell-macos/examples/` to prove the point of the first rule below.

There are **no symlinks** anywhere in this layout. `quickshell-macos/shell` and
`quickshell-macos/examples/` used to point here and are gone; every path is
written out in full instead. If a script needs a config, it says
`$HOME/.config/quickshell/<name>` — never a relative walk up from its own
location, which is what silently broke `switchwall.sh` when the config moved.

Inside `end4`, the panel modules are flat: `modules/bar`, `modules/dock`,
`modules/overview` — not `modules/ii/...` as upstream ships them. The panel
family that used to be called `ii` is `main`; `waffle` is unchanged. The stored
`panelFamily` in `~/Library/Preferences/illogical-impulse/config.json` was
migrated to match, so a config.json restored from an older backup will name a
family that no longer exists and load no panels.

## Rules

- Commit config changes rather than leaving them untracked. Untracked files have
  no history, so two sessions editing one file silently overwrite each other —
  that is what this layout exists to prevent.
- Never point a script at `~/.claude/jobs/*/tmp`. Those are scratch dirs deleted
  with the job; two scripts once built from one.
- `karabiner.json` and `skhd/skhdrc` call `qs-ipc` by **absolute path** because
  Karabiner does not expand `~`. `install.sh` rewrites them; keep it that way.
- `gh/` is gitignored — `hosts.yml` holds an OAuth token.
- Compiled helpers and built binaries are gitignored everywhere. The sources and
  the compiler calls that build them are committed instead.
