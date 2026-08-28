pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Spaces, via yabai's query socket.
//
// This is the macOS stand-in for Quickshell.Hyprland's workspace model. macOS
// has no public Spaces API at all, so a window manager that already tracks them
// is the only sane source. yabai's *queries* work with SIP fully enabled; only
// its space-manipulation features need SIP disabled, and we use none of those.
Singleton {
    id: root

    // [{ index, focused, visible, display, windowCount }]
    property list<var> list: []
    property int focusedIndex: -1
    readonly property int count: list.length
    readonly property bool available: count > 0

    function focus(index: int): void {
        dispatch.exec(["yabai", "-m", "space", "--focus", String(index)]);
        refresh();
    }

    function focusNext(): void {
        dispatch.exec(["sh", "-c", "yabai -m space --focus next || yabai -m space --focus first"]);
        refresh();
    }

    function focusPrev(): void {
        dispatch.exec(["sh", "-c", "yabai -m space --focus prev || yabai -m space --focus last"]);
        refresh();
    }

    function missionControl(): void {
        dispatch.exec(["open", "-b", "com.apple.exposelauncher"]);
    }

    function refresh(): void {
        query.running = true;
    }

    Process {
        id: dispatch
    }

    Process {
        id: query

        running: true
        command: ["yabai", "-m", "query", "--spaces"]

        stdout: StdioCollector {
            onStreamFinished: {
                let spaces;
                try {
                    spaces = JSON.parse(text);
                } catch (e) {
                    return;
                }
                if (!Array.isArray(spaces))
                    return;

                const mapped = spaces.map(s => ({
                            index: s.index,
                            focused: s["has-focus"] === true,
                            visible: s["is-visible"] === true,
                            display: s.display,
                            windowCount: (s.windows ?? []).length
                        }));

                // Only reassign when something actually changed — the list is
                // bound to animating delegates and a redundant reset makes the
                // whole dot cluster flicker.
                if (JSON.stringify(mapped) === JSON.stringify(root.list))
                    return;

                root.list = mapped;
                const focused = mapped.find(s => s.focused);
                root.focusedIndex = focused ? focused.index : -1;
            }
        }
    }

    Timer {
        interval: 500
        running: true
        repeat: true
        onTriggered: root.refresh()
    }
}
