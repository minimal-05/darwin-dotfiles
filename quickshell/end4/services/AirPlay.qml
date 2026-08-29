pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * AirPlay receivers on the local network, browsed over Bonjour.
 *
 * Discovery is all this can do. Starting a mirroring session needs
 * AVOutputContext's system screen context, which returns nil to every process
 * without Apple's own entitlement — checked, not assumed — so the connection
 * itself has to be handed to Apple's picker. See ScreenMirroringDialog.
 */
Singleton {
    id: root

    // Device names, sorted. Bonjour reports one record per interface, so the
    // same receiver arrives two or three times over.
    property var devices: []
    property bool scanning: false

    property var seen: ({})

    function start(): void {
        root.seen = {};
        root.devices = [];
        root.scanning = true;
        browse.running = false;
        browse.running = true;
        settle.restart();
    }

    function stop(): void {
        settle.stop();
        browse.running = false;
        root.scanning = false;
    }

    function publish(): void {
        root.devices = Object.keys(root.seen).sort((a, b) => a.localeCompare(b));
    }

    Timer {
        id: settle

        // `dns-sd -B` browses forever. The first burst lands at once and
        // stragglers trickle in, so this only decides when to stop saying so.
        interval: 4000
        onTriggered: root.scanning = false
    }

    Process {
        id: browse

        command: ["dns-sd", "-B", "_airplay._tcp", "local."]

        stdout: SplitParser {
            onRead: line => {
                // 11:34:57.611  Add  3  14 local.  _airplay._tcp.  Family Room
                const match = line.match(/^\S+\s+(Add|Rmv)\s+\d+\s+\d+\s+\S+\s+\S+\s+(.*\S)\s*$/);
                if (!match)
                    return;
                const name = match[2];
                // This Mac publishes itself as "." — never a receiver worth listing.
                if (name === "." || name.length === 0)
                    return;
                if (match[1] === "Add")
                    root.seen[name] = true;
                else
                    delete root.seen[name];
                root.publish();
            }
        }
    }
}
