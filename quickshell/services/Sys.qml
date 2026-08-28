pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// CPU and memory. Both are cheap enough to shell out for at this cadence
// (~30ms per sample); a native backend would use host_statistics64 directly.
Singleton {
    id: root

    property real cpuUsage: 0        // 0-100, normalised across cores
    property int memoryFreePercent: -1
    readonly property int memoryUsedPercent: memoryFreePercent >= 0 ? 100 - memoryFreePercent : -1

    // Rolling window for the sparkline. Oldest first.
    property list<real> cpuHistory: []
    readonly property int historyLength: 40

    readonly property color cpuColor: cpuUsage > 80 ? "#ffF2B8B5" : cpuUsage > 50 ? "#ffE8C48A" : "#ffA8D5A2"

    function pushHistory(value: real): void {
        const next = root.cpuHistory.slice();
        next.push(value);
        while (next.length > root.historyLength)
            next.shift();
        root.cpuHistory = next;
    }

    Process {
        id: cpuProc

        running: true
        command: ["sh", "-c", "ps -A -o %cpu= | awk -v n=$(sysctl -n hw.ncpu) '{s+=$1} END {printf \"%.1f\", s/n}'"]

        stdout: StdioCollector {
            onStreamFinished: {
                const value = parseFloat(text.trim());
                if (isNaN(value))
                    return;
                root.cpuUsage = Math.min(100, value);
                root.pushHistory(root.cpuUsage);
            }
        }
    }

    Process {
        id: memProc

        running: true
        command: ["sh", "-c", "memory_pressure | awk '/free percentage/ {gsub(/%/,\"\"); print $NF}'"]

        stdout: StdioCollector {
            onStreamFinished: {
                const value = parseInt(text.trim(), 10);
                if (!isNaN(value))
                    root.memoryFreePercent = value;
            }
        }
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: {
            cpuProc.running = true;
            memProc.running = true;
        }
    }
}
