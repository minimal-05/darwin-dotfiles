# darwin-dotfiles — where things live

This repo (`~/.config`, remote `minimal-05/darwin-dotfiles`) is the **canonical
home for all live config**. If a config file is loaded by a running program, it
lives here and nowhere else.

## The quickshell split — read this before editing any .qml

Three directories have "quickshell" in the name. They are not copies of each
other, and only the first holds config:

| Path | What it is | Edit it? |
|---|---|---|
| `~/.config/quickshell` | **The shell config.** `qs-switch mine` runs `shell.qml` from here. | **Yes — this is the only place.** |
| `~/Projects/quickshell-macos` | The *runtime*: the built `bin/quickshell` binary, the `qs-*` launcher scripts, shims, end-4 example. | Only for scripts/binary, never for shell config. |
| `~/Projects/quickshell-src` | Upstream C++ checkout + our unpushed **Cocoa backend** work. | Only for C++/backend changes. |

`~/Projects/quickshell-macos/shell` is a **symlink** to `~/.config/quickshell`.
It is not a second copy — do not "fix" it by replacing it with a directory.

`~/Projects/qs-macos-spike` is a stale upstream checkout with no Cocoa backend.
Nothing uses it. Do not edit it; prefer `~/Projects/quickshell-src`.

## Rules

- Changing the bar, pills, or services → `~/.config/quickshell`, then commit here.
- Changing how the shell is launched/built → `~/Projects/quickshell-macos/bin`.
- Changing the C++ backend → `~/Projects/quickshell-src`, then `qs-dev`.
- Never point a script at `~/.claude/jobs/*/tmp`. Those are scratch dirs that get
  deleted with the job; two scripts used to build from one and nearly lost the
  whole Cocoa backend.
- Commit config changes here rather than leaving them untracked. Untracked files
  have no history, so two sessions editing the same file silently overwrite each
  other — that is what this layout exists to prevent.
- `gh/` is gitignored: `hosts.yml` holds an OAuth token. Keep it that way.
