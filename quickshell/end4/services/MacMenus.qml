pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * The frontmost app's menu bar, and Apple's own menu extras, over Accessibility.
 *
 * `menus` is the AX helper the SketchyBar config uses. It stays where it is on
 * purpose: macOS grants Accessibility per binary path, so copying it in here
 * would mean granting it a second time.
 */
Singleton {
    id: root

    // Bare name, resolved from PATH like notify-send and pidof: the binary puts
    // Quickshell.app/Contents/Resources/tools first. It used to be an absolute
    // path into the SketchyBar config, which is gone.
    readonly property string bin: "menus"

    // Top-level menus of the frontmost app, [{ id, title }]. `-l` prints menu 1
    // onwards, so line N is menu N — menu 0 is Apple's and is never listed.
    property var titles: []

    // Entries of the menu currently open, [{ id, title, shortcut }]. The ids are
    // the helper's own and are not contiguous: separators are skipped, not
    // renumbered, so they cannot be replaced with a list index.
    property int openMenu: -1
    property var entries: []

    // Entries already read this time the dropdown was opened, by menu id. The
    // helper costs 20-90ms a call, which is enough to feel when it lands on
    // every pass over a menu title; going back to one is then free.
    property var cache: ({})

    // The app the menus were read from, captured while the dropdown opens and
    // before any click of ours can change it. Clicking a shell surface makes
    // quickshell the frontmost application -- its windows are plain QNSWindows,
    // not NSPanels, so AppKit's nonactivating panel style cannot apply -- and
    // the helper presses menu items of whatever is frontmost.
    property int targetPid: -1

    // Set when the helper returns no menus at all, which in practice only
    // happens once it has lost its Accessibility grant.
    property bool blocked: false

    function refresh(): void {
        // The frontmost app may have changed since last time, so the cache from
        // the previous open cannot be trusted.
        root.cache = {};
        frontPid.running = false;
        frontPid.running = true;
        list.running = false;
        list.running = true;
    }

    function open(menu: int): void {
        root.openMenu = menu;

        const cached = root.cache[menu];
        if (cached !== undefined) {
            root.entries = cached;
            return;
        }

        root.entries = [];
        fetch.menuId = menu;
        fetch.running = false;
        fetch.command = [root.bin, "-i", String(menu)];
        fetch.running = true;
    }

    function close(): void {
        root.openMenu = -1;
        root.entries = [];
    }

    function press(menu: int, entry: int): void {
        const command = `'${root.bin}' -p ${menu} ${entry}`;

        if (root.targetPid <= 0) {
            Quickshell.execDetached(["sh", "-c", command]);
            root.close();
            return;
        }

        // Bring the app back to the front before pressing, and wait until it
        // actually is: activation is asynchronous, and pressing early sends the
        // command to whatever is still frontmost. The bundle comes from the pid
        // rather than the menu title, which is not always the app's name --
        // VS Code's menu says "Code".
        const pid = root.targetPid;
        Quickshell.execDetached(["sh", "-c", `
            app=$(ps -p ${pid} -o comm= 2>/dev/null | sed 's#/Contents/MacOS/.*##')
            [ -n "$app" ] && open -a "$app"
            i=0
            while [ $i -lt 40 ]; do
                front=$(lsappinfo info -only pid "$(lsappinfo front)" 2>/dev/null | sed 's/.*=//')
                [ "$front" = "${pid}" ] && break
                i=$((i + 1))
                sleep 0.02
            done
            ${command}
        `]);
        root.close();
    }

    function grantAccessibility(): void {
        Quickshell.execDetached(["open", "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"]);
    }

    /**
     * Drops Apple's own Control Centre, by clicking its menu extra. Screen
     * Mirroring has no scriptable API and no menu extra of its own, so this is
     * the only route to actually starting a session. See ScreenMirroringDialog.
     */
    function controlCentre(): void {
        Quickshell.execDetached([root.bin, "-s", "Control Center,BentoBox"]);
    }

    Process {
        id: frontPid

        // lsappinfo's notion of the front application is the same one the AX
        // helper uses, and it costs about 10ms.
        command: ["sh", "-c", "lsappinfo info -only pid \"$(lsappinfo front)\" 2>/dev/null | sed 's/.*=//'"]

        stdout: StdioCollector {
            onStreamFinished: {
                const pid = parseInt(text.trim());
                root.targetPid = isNaN(pid) ? -1 : pid;
            }
        }
    }

    Process {
        id: list

        command: [root.bin, "-l"]

        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                const lines = text.split("\n");
                for (let i = 0; i < lines.length; i++) {
                    const title = lines[i];
                    // Some apps publish their window title into the menu bar. It
                    // is never a real menu, and never this short.
                    if (!title || title.length > 32 || title.startsWith("::") || title.includes("✳"))
                        continue;
                    out.push({
                        id: i + 1,
                        title: title
                    });
                }
                root.titles = out;
                root.blocked = out.length === 0;
            }
        }
    }

    Process {
        id: fetch

        property int menuId: -1

        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                const lines = text.split("\n");
                for (const line of lines) {
                    const parts = line.split("\t");
                    if (parts.length < 2 || !parts[1])
                        continue;
                    out.push({
                        id: parseInt(parts[0]),
                        title: parts[1],
                        shortcut: parts[2] ?? ""
                    });
                }

                if (out.length === 0) {
                    // A menu the app builds lazily reads as empty until it has
                    // been dropped once. Don't cache that, or it stays empty.
                    Quickshell.execDetached([root.bin, "-s", String(fetch.menuId)]);
                } else {
                    root.cache[fetch.menuId] = out;
                }

                if (root.openMenu === fetch.menuId)
                    root.entries = out;
            }
        }
    }
}
