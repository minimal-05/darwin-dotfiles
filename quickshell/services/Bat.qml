pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Battery state from pmset. IOKit would be cleaner but needs a native backend;
// pmset is stable, permission-free, and cheap enough at this interval.
Singleton {
    id: root

    property int percentage: -1
    property bool charging: false
    property bool onAcPower: false
    property string timeRemaining: ""
    readonly property bool available: percentage >= 0

    readonly property string icon: {
        if (!available)
            return "󰂑";
        if (charging)
            return "󰂄";
        if (percentage > 80)
            return "󰁹";
        if (percentage > 60)
            return "󰂀";
        if (percentage > 40)
            return "󰁾";
        if (percentage > 20)
            return "󰁻";
        return "󰁺";
    }

    function refresh(): void {
        proc.running = true;
    }

    Process {
        id: proc

        running: true
        command: ["pmset", "-g", "batt"]

        stdout: StdioCollector {
            onStreamFinished: {
                const out = text;
                const pct = out.match(/(\d+)%/);

                if (!pct) {
                    root.percentage = -1;
                    return;
                }

                root.percentage = parseInt(pct[1], 10);
                root.onAcPower = out.includes("AC Power");
                root.charging = /;\s*(charging|finishing charge)/i.test(out);

                const time = out.match(/(\d+:\d\d)\s+remaining/);
                root.timeRemaining = time ? time[1] : "";
            }
        }
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }
}
