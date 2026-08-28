pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Throughput and link state for whichever interface currently carries the
// default route. Rates are deltas between samples, so the first sample after
// startup or an interface change is discarded rather than shown as a spike.
Singleton {
    id: root

    property string iface: ""
    property string ssid: ""
    property bool wifi: false

    property real downBytesPerSec: 0
    property real upBytesPerSec: 0

    property real lastDown: -1
    property real lastUp: -1
    property real lastSample: 0

    readonly property string icon: wifi ? "󰖩" : iface.length > 0 ? "󰈀" : "󰤭"
    readonly property string label: wifi && ssid.length > 0 ? ssid : iface.length > 0 ? "Wired" : "Offline"

    function formatRate(bytesPerSec: real): string {
        if (bytesPerSec < 1024)
            return `${Math.round(bytesPerSec)} B/s`;
        if (bytesPerSec < 1024 * 1024)
            return `${(bytesPerSec / 1024).toFixed(0)} KB/s`;
        return `${(bytesPerSec / 1024 / 1024).toFixed(1)} MB/s`;
    }

    Process {
        id: ifaceProc

        running: true
        command: ["sh", "-c", "route -n get default 2>/dev/null | awk '/interface:/ {print $2}'"]

        stdout: StdioCollector {
            onStreamFinished: {
                const name = text.trim();
                if (name === root.iface)
                    return;

                root.iface = name;
                root.lastDown = -1;   // interface changed: counters are unrelated
                root.lastUp = -1;
                ssidProc.running = true;
            }
        }
    }

    Process {
        id: ssidProc

        command: ["sh", "-c", `networksetup -getairportnetwork ${root.iface || "en0"} 2>/dev/null`]

        stdout: StdioCollector {
            onStreamFinished: {
                const match = text.match(/Current Wi-Fi Network:\s*(.+)/);
                root.wifi = match !== null;
                root.ssid = match ? match[1].trim() : "";
            }
        }
    }

    Process {
        id: statsProc

        command: ["sh", "-c", `netstat -ib -I ${root.iface || "en0"} 2>/dev/null | awk 'NR==2 {print $7, $10}'`]

        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split(/\s+/);
                if (parts.length < 2)
                    return;

                const down = parseFloat(parts[0]);
                const up = parseFloat(parts[1]);
                if (isNaN(down) || isNaN(up))
                    return;

                const now = Date.now();
                const elapsed = (now - root.lastSample) / 1000;

                if (root.lastDown >= 0 && elapsed > 0) {
                    // Counters reset on link flap; a negative delta is not a rate.
                    root.downBytesPerSec = Math.max(0, (down - root.lastDown) / elapsed);
                    root.upBytesPerSec = Math.max(0, (up - root.lastUp) / elapsed);
                }

                root.lastDown = down;
                root.lastUp = up;
                root.lastSample = now;
            }
        }
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            statsProc.running = true;
            ifaceProc.running = true;
        }
    }
}
