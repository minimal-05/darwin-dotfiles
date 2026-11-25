#!/usr/bin/env python3
#
# Trash and Put Back for the shell's file manager and image viewer.
#
#   put-back.py --trash <path>...   move to the Trash through Finder, noting where each came from
#   put-back.py <trashed path>...   move each item back where it came from
#   put-back.py --list              print every item's original location
#
# Finder has no AppleScript verb for Put Back, so this keeps its own ledger:
# --trash records each item's inode, where it landed in the Trash and where it
# came from. The inode is what makes a line trustworthy -- a move into the
# Trash on the same volume is a rename and keeps it, so a stale line for some
# other file that later took the same name can never match.
#
# Items trashed by anything else (Finder itself, other apps) fall back to
# Finder's own record: `ptbL`/`ptbN` in the Trash's .DS_Store. Finder writes
# that lazily -- sometimes seconds, sometimes minutes after the delete -- which
# is why the ledger comes first rather than being a nicety.
#
# Reading ~/.Trash needs Full Disk Access for whoever runs this.

import json
import os
import shutil
import struct
import subprocess
import sys

TRASH = os.path.expanduser("~/.Trash")
# A fixed path rather than Qt's StateLocation: that is per app bundle, and the
# file manager and the image viewer both have to see the same ledger.
LEDGER = os.path.expanduser("~/Library/Preferences/quickshell/State/user/put-back.tsv")


def put_back_records(ds_store: str) -> dict:
    """{trashed name: {"ptbL": folder, "ptbN": name}} from a .DS_Store.

    The format is a buddy-allocated B-tree; see
    https://metacpan.org/dist/Mac-Finder-DSStore/view/DSStoreFormat.pod.
    Every offset in the file is relative to byte 4.
    """
    data = open(ds_store, "rb").read()
    if data[4:8] != b"Bud1":
        raise ValueError(f"{ds_store}: not a .DS_Store")

    def u32(o):
        return struct.unpack_from(">I", data, o)[0]

    info = u32(8) + 4
    nblocks = u32(info)
    addrs = [u32(info + 8 + 4 * i) for i in range(nblocks)]
    p = info + 8 + 4 * ((nblocks + 255) // 256 * 256)
    dirs = {}
    count, p = u32(p), p + 4
    for _ in range(count):
        n = data[p]
        dirs[data[p + 1:p + 1 + n].decode()] = u32(p + 1 + n)
        p += 1 + n + 4

    def block(i):
        return (addrs[i] & ~0x1F) + 4

    out = {}

    def record(o):
        n = u32(o)
        name = data[o + 4:o + 4 + 2 * n].decode("utf-16-be")
        o += 4 + 2 * n
        code, kind = data[o:o + 4].decode(), data[o + 4:o + 8]
        o += 8
        val = None
        if kind in (b"long", b"shor", b"type"):
            o += 4
        elif kind == b"bool":
            o += 1
        elif kind in (b"comp", b"dutc"):
            o += 8
        elif kind == b"blob":
            o += 4 + u32(o)
        elif kind == b"ustr":
            n = u32(o)
            val = data[o + 4:o + 4 + 2 * n].decode("utf-16-be")
            o += 4 + 2 * n
        else:
            raise ValueError(f"unknown record type {kind!r}")
        if code in ("ptbL", "ptbN"):
            out.setdefault(name, {})[code] = val
        return o

    def walk(b):
        o = block(b)
        right, count = u32(o), u32(o + 4)
        o += 8
        for _ in range(count):
            if right:  # internal node: each record follows its left child
                walk(u32(o))
                o += 4
            o = record(o)
        if right:
            walk(right)

    walk(u32(block(dirs["DSDB"])))
    return out


def original_path(rec: dict, trashed_name: str) -> str:
    return os.path.join("/" + rec["ptbL"], rec.get("ptbN") or trashed_name)


def notify(message: str) -> None:
    # The file manager runs this detached, so a failure would otherwise vanish.
    # AppleScript string literals escape the same way JSON does.
    subprocess.run(["osascript", "-e", f'display notification {json.dumps(message)} with title "Put Back"'])


def inode(path: str):
    try:
        return os.lstat(path).st_ino
    except OSError:
        return None


def read_ledger() -> dict:
    """{trashed path: original path}, only for lines whose inode still matches."""
    out = {}
    try:
        lines = open(LEDGER).read().splitlines()
    except FileNotFoundError:
        return out
    for line in lines:
        ino, trashed, original = line.split("\t")
        if inode(trashed) == int(ino):
            out[trashed] = original
    return out


def write_ledger(entries: dict) -> None:
    # Rewritten whole each time, keeping only lines that still match: emptied
    # and put-back items fall out, so the file never grows past the Trash.
    os.makedirs(os.path.dirname(LEDGER), exist_ok=True)
    with open(LEDGER, "w") as f:
        for trashed, original in entries.items():
            ino = inode(trashed)
            if ino is not None:
                f.write(f"{ino}\t{trashed}\t{original}\n")


# Finder's delete returns a reference to where each item landed -- renamed, if
# the Trash already held that name. argv sidesteps quoting paths into source.
TRASH_SCRIPT = """
on run argv
    set targets to {}
    repeat with p in argv
        set end of targets to ((p as text) as POSIX file)
    end repeat
    tell application "Finder" to set landed to delete targets
    if class of landed is not list then set landed to {landed}
    set out to {}
    repeat with f in landed
        set end of out to POSIX path of (f as alias)
    end repeat
    set AppleScript's text item delimiters to linefeed
    return out as text
end run
"""


def trash(paths: list) -> int:
    before = {inode(p): os.path.abspath(p).rstrip("/") for p in paths}
    res = subprocess.run(["osascript", "-", *paths], input=TRASH_SCRIPT, capture_output=True, text=True)
    if res.returncode != 0:
        notify(res.stderr.strip() or "Could not move to Trash")
        return 1
    ledger = read_ledger()
    for landed in res.stdout.splitlines():
        landed = landed.rstrip("/")
        original = before.get(inode(landed))
        if original:
            ledger[landed] = original
    write_ledger(ledger)
    return 0


def main(argv: list) -> int:
    if argv[:1] == ["--trash"]:
        return trash(argv[1:])

    ledger = read_ledger()
    records = put_back_records(os.path.join(TRASH, ".DS_Store"))
    if argv == ["--list"]:
        for name, rec in sorted(records.items()):
            if "ptbL" in rec:
                print(f"{name}\t{original_path(rec, name)}")
        for trashed, original in ledger.items():
            print(f"{os.path.basename(trashed)}\t{original}\t(ledger)")
        return 0

    failed = []
    for path in argv:
        path = path.rstrip("/")
        name = os.path.basename(path)
        dest = ledger.get(path)
        if not dest:
            rec = records.get(name)
            if not rec or "ptbL" not in rec:
                failed.append(f"{name}: no original location recorded")
                continue
            dest = original_path(rec, name)
        # Never overwrite: something new has taken the old name since.
        if os.path.lexists(dest):
            failed.append(f"{name}: {dest} already exists")
            continue
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        shutil.move(path, dest)
    write_ledger(ledger)
    if failed:
        print("\n".join(failed), file=sys.stderr)
        notify("; ".join(failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
