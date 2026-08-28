pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The frontmost application and its window title.
//
// yabai is asked rather than System Events because AppleScript against another
// process triggers an Automation permission prompt, and yabai already holds the
// permissions it needs.
Singleton {
    id: root

    property string appName: ""
    property string title: ""
    readonly property bool available: appName.length > 0

    function refresh(): void {
        query.running = true;
    }

    Process {
        id: query

        running: true
        command: ["yabai", "-m", "query", "--windows", "--window"]

        stdout: StdioCollector {
            onStreamFinished: {
                let win;
                try {
                    win = JSON.parse(text);
                } catch (e) {
                    return;
                }

                root.appName = win.app ?? "";
                root.title = win.title ?? "";
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
