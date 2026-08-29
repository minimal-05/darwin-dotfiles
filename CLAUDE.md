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

`~/.config/quickshell` **is** end-4's illogical-impulse, adapted for macOS —
third party, its own licence, ~960 files. It is tracked here anyway: it is live
config that gets edited constantly, and it spent long enough untracked under
`quickshell-macos/examples/` to prove the point of the first rule below.

The hand-written bar that used to live here was removed on 2026-08-29, so there
is one quickshell config now rather than two competing ones. It is still in
history: `git log --diff-filter=D -- quickshell/shell.qml`.

`~/Projects/quickshell-macos/shell` and `~/Projects/quickshell-macos/examples/end4-ii`
are both **symlinks** back to `~/.config/quickshell`. Neither is a second copy —
do not replace either with a directory. The `examples/end4-ii` one exists only so
paths that still name the old location keep resolving; new code should say
`~/.config/quickshell`.

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
