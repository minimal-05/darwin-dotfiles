pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * AirPlay receivers on the local network, browsed over Bonjour, plus a
 * mirroring connect/disconnect notification.
 *
 * Discovery is all this can *drive*. Starting a mirroring session needs
 * AVOutputContext's system screen context, which returns nil to every process
 * without Apple's own entitlement — checked, not assumed — so the connection
 * itself has to be handed to Apple's picker. See ScreenMirroringDialog.
 *
 * Discovery runs for the shell's whole lifetime, not just while the picker is
 * open, so the dialog always opens with a populated list instead of a blank
 * spinner. ponytail: this used to also notify on every receiver
 * appear/disappear, but mDNS visibility over a real network flaps far too
 * often for that to be tolerable without a debounce window (84 notifications
 * in 8h, 2026-09-02) -- dropped rather than tuned, since nobody asked for it.
 */
Singleton {
    id: root

    // Device names, sorted. Bonjour reports one record per interface, so the
    // same receiver arrives two or three times over.
    property var devices: []
    property bool scanning: true

    property var seen: ({})

    // Suppresses the mirroring notification for the very first check — the
    // backlog system_profiler reports on startup was already true before the
    // shell existed, not something that just happened.
    property bool initialized: false

    // Singletons instantiate lazily on first reference; shell.qml calls this
    // at startup so discovery (and the mirroring watcher below) starts right
    // away instead of waiting for the picker dialog to be opened once.
    function load(): void {
        // dummy to force init
    }

    // ScreenMirroringDialog's "search again" button: dns-sd is already
    // running continuously, so this only re-shows the spinner briefly.
    function start(): void {
        root.scanning = true;
        settle.restart();
    }

    function publish(): void {
        root.devices = Object.keys(root.seen).sort((a, b) => a.localeCompare(b));
    }

    function notify(body): void {
        Quickshell.execDetached(["notify-send", "AirPlay", body, "-a", "AirPlay"]);
    }

    Timer {
        id: settle

        // `dns-sd -B` browses forever. The first burst lands at once and
        // stragglers trickle in, so this only decides when to stop saying so.
        interval: 4000
        running: true
        onTriggered: {
            root.scanning = false;
            root.initialized = true;
        }
    }

    Process {
        id: browse
        running: true

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

    // ---- screen mirroring: connect/disconnect notifications --------------
    //
    // There is no API here that reports "a mirroring session is active" (see
    // the class comment). A mirrored receiver does show up as a display
    // though: system_profiler reports its spdisplays_connection_type as
    // "spdisplays_airplay", distinct from every real connector (internal,
    // hdmi, displayport, usb). Driven by Quickshell.screens changing rather
    // than polled, so this only runs on an actual display-topology change.
    property var mirroring: ({}) // display name -> true

    Connections {
        target: Quickshell
        function onScreensChanged(): void {
            displayCheck.running = true;
        }
    }

    Process {
        id: displayCheck
        command: ["system_profiler", "SPDisplaysDataType", "-json"]
        stdout: StdioCollector {
            id: displayCheckOutput
            onStreamFinished: {
                let gpus;
                try {
                    gpus = JSON.parse(displayCheckOutput.text).SPDisplaysDataType ?? [];
                } catch (e) {
                    return;
                }
                const nowMirroring = {};
                for (const gpu of gpus) {
                    for (const display of gpu.spdisplays_ndrvs ?? []) {
                        if (!(display.spdisplays_connection_type ?? "").includes("airplay"))
                            continue;
                        const name = display._name || "AirPlay";
                        nowMirroring[name] = true;
                        if (!root.mirroring[name] && root.initialized)
                            root.notify(`Mirroring to ${name}`);
                    }
                }
                for (const name in root.mirroring) {
                    if (!nowMirroring[name] && root.initialized)
                        root.notify(`Stopped mirroring to ${name}`);
                }
                root.mirroring = nowMirroring;
            }
        }
    }

    Component.onCompleted: displayCheck.running = true
}
