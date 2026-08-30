#!/usr/bin/env python3
"""Set the macOS desktop picture in every wallpaper scope.

`osascript -e 'tell application "System Events" to set picture of every desktop'`
reaches exactly one scope: the Space you happen to be standing on. macOS keeps
the rest in its own store -- every other Space, each display, and SystemDefault,
which is what the login window draws before any user session exists -- and they
keep whatever they last held. That is why the login screen, System Settings and
the desktop can each show a different image, and why the "Show on all Spaces"
toggle flips itself back off: a per-Space write is what puts it there.

Sequoia has no public API for the other scopes -- desktoppicture.db is gone --
so this writes the store directly and restarts WallpaperAgent to pick it up.
Only the Files list of each Desktop node is rewritten. The Configuration blob
(fill mode, matte colour) is left exactly as macOS wrote it, and Idle nodes are
not touched at all: that is the screen saver, a separate setting and not ours
to redefine.

Usage:  set-desktop-picture.py <image>
        set-desktop-picture.py --self-check
"""

import os
import pathlib
import plistlib
import subprocess
import sys
import time

INDEX = pathlib.Path.home() / "Library/Application Support/com.apple.wallpaper/Store/Index.plist"
IMAGE_PROVIDER = "com.apple.wallpaper.choice.image"


def retarget(node, url):
    """Point every Desktop node in the tree at url. Returns how many it changed.

    The store nests Desktop nodes at several depths -- SystemDefault.Desktop,
    Spaces.<uuid>.Default.Desktop, Spaces.<uuid>.Displays.<uuid>.Desktop,
    Displays.<uuid>.Desktop -- so this recurses rather than naming each path.
    """
    if not isinstance(node, dict):
        return 0
    changed = 0
    for key, value in node.items():
        if key == "Desktop" and isinstance(value, dict) and "Content" in value:
            for choice in value["Content"].get("Choices", []):
                choice["Provider"] = IMAGE_PROVIDER
                choice["Files"] = [{"relative": url}]
                changed += 1
        elif key != "Idle":
            changed += retarget(value, url)
    return changed


def self_check():
    # One synthetic store shaped like the real one: a Desktop at each depth the
    # walk has to reach, plus Idle nodes that must come out untouched.
    def idle():
        return {"Content": {"Choices": [
            {"Provider": "com.apple.wallpaper.choice.screen-saver", "Files": []}]}}

    def desktop():
        return {"Content": {"Choices": [
            {"Provider": "x", "Files": [{"relative": "file:///old.png"}],
             "Configuration": b"keep"}]}}

    store = {
        "SystemDefault": {"Desktop": desktop(), "Idle": idle()},
        "AllSpacesAndDisplays": {"Idle": idle()},
        "Spaces": {"s1": {"Default": {"Desktop": desktop(), "Idle": idle()},
                          "Displays": {"d1": {"Desktop": desktop()}}}},
        "Displays": {"d1": {"Desktop": desktop(), "Idle": idle()}},
    }

    assert retarget(store, "file:///new.png") == 4, "expected to reach all four Desktop nodes"

    found = []

    def collect(node):
        if not isinstance(node, dict):
            return
        for key, value in node.items():
            if key == "Desktop":
                found.append(value["Content"]["Choices"][0])
            else:
                collect(value)

    collect(store)
    assert len(found) == 4, found
    for choice in found:
        assert choice["Files"] == [{"relative": "file:///new.png"}], choice
        assert choice["Provider"] == IMAGE_PROVIDER, choice
        assert choice["Configuration"] == b"keep", "Configuration must survive"

    # Idle is the screen saver and stays as it was.
    assert store["SystemDefault"]["Idle"]["Content"]["Choices"][0]["Files"] == []
    assert store["AllSpacesAndDisplays"]["Idle"]["Content"]["Choices"][0]["Provider"] \
        == "com.apple.wallpaper.choice.screen-saver"

    # A store with nothing to retarget must say so rather than report success.
    assert retarget({"Idle": idle()}, "file:///new.png") == 0
    print("self-check ok")


def main():
    if sys.argv[1:2] == ["--self-check"]:
        return self_check()

    if len(sys.argv) != 2:
        sys.exit(__doc__)

    image = pathlib.Path(sys.argv[1]).expanduser().resolve()
    if not image.is_file():
        sys.exit(f"set-desktop-picture: not a readable file: {image}")
    if not INDEX.is_file():
        sys.exit(f"set-desktop-picture: no wallpaper store at {INDEX}")

    store = plistlib.loads(INDEX.read_bytes())
    changed = retarget(store, image.as_uri())
    if changed == 0:
        sys.exit("set-desktop-picture: no Desktop entry in the wallpaper store")

    # Stop the agent before writing. It holds the store in memory and writes it
    # back out on the way down, which would put the old picture straight back.
    subprocess.run(["killall", "WallpaperAgent"], capture_output=True)
    for _ in range(50):
        if subprocess.run(["pgrep", "-x", "WallpaperAgent"], capture_output=True).returncode != 0:
            break
        time.sleep(0.1)

    INDEX.write_bytes(plistlib.dumps(store))

    # launchd runs the agent on demand, so it comes back by itself; kickstart
    # only saves us waiting for whatever would have asked for it first.
    subprocess.run(
        ["launchctl", "kickstart", f"gui/{os.getuid()}/com.apple.wallpaper.agent"],
        capture_output=True)
    print(f"set-desktop-picture: {changed} scopes -> {image}")


if __name__ == "__main__":
    main()
