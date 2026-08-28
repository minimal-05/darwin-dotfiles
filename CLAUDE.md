# darwin-dotfiles — where things live

This repo (`~/.config`) is the **canonical home for live config**. If a config
file is loaded by a running program, it lives here — with two exceptions below,
which are their own repos because they carry build steps of their own.

## Three repos, not one

| Path | Repo | Holds |
|---|---|---|
| `~/.config` | `darwin-dotfiles` | everything here — yabai, skhd, karabiner, kitty, nvim, borders, btop, nnn, starship, **and the quickshell shell config** |
| `~/.config/sketchybar` | `sketchybar` | the bar. Nested repo, **gitignored here** — do not `git add` it |
| `~/Projects/quickshell-macos` | `quickshell-macos` | the C++ Cocoa fork **and** its `bin/qs-*` launchers |

`./install.sh` clones the other two and wires them up.

## The quickshell split — read before editing any .qml

- **Bar, pills, services** → `~/.config/quickshell` (here, in this repo).
- **C++ backend, launchers, shims** → `~/Projects/quickshell-macos`.

`~/Projects/quickshell-macos/shell` is a **symlink** back to
`~/.config/quickshell`. It is not a second copy — do not replace it with a
directory.

`~/Projects/qs-macos-spike` is a stale checkout with no Cocoa backend and
nothing uses it. Don't edit it.

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
