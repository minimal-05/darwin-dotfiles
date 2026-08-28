pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Now playing, via media-control's MediaRemote adapter.
//
// Apple entitlement-gated the MediaRemote read path in macOS 15.4, so nothing
// reads now-playing directly any more. media-control works around it by having
// Apple-signed /usr/bin/perl load the adapter framework. That makes this the
// most fragile service here: it can break on any macOS point release, so every
// consumer must tolerate `available` going false.
Singleton {
    id: root

    property string title: ""
    property string artist: ""
    property string album: ""
    property string bundleId: ""
    property bool playing: false
    property real elapsed: 0
    property real duration: 0

    readonly property bool available: title.length > 0
    readonly property string icon: playing ? "󰏤" : "󰐊"

    readonly property string appName: {
        if (bundleId.startsWith("com.spotify"))
            return "Spotify";
        if (bundleId.includes("Music") || bundleId.includes("iTunes"))
            return "Music";
        if (bundleId.includes("firefox"))
            return "Firefox";
        if (bundleId.includes("Safari"))
            return "Safari";
        if (bundleId.includes("chrome") || bundleId.includes("Chrome"))
            return "Chrome";
        return "";
    }

    function playPause(): void {
        control.exec(["media-control", "toggle-play-pause"]);
    }

    function next(): void {
        control.exec(["media-control", "next-track"]);
    }

    function previous(): void {
        control.exec(["media-control", "previous-track"]);
    }

    function apply(payload: var): void {
        if (!payload || typeof payload !== "object")
            return;

        // A stream frame with no payload keys means nothing is playing any more.
        if (payload.payload !== undefined)
            payload = payload.payload;

        root.title = payload.title ?? "";
        root.artist = payload.artist ?? "";
        root.album = payload.album ?? "";
        root.bundleId = payload.bundleIdentifier ?? "";
        root.playing = payload.playing === true;
        root.elapsed = payload.elapsedTime ?? 0;
        root.duration = payload.duration ?? 0;
    }

    Process {
        id: control
    }

    // Long-lived stream: one JSON object per line, artwork stripped because we
    // never show it and it dwarfs everything else in the payload.
    Process {
        id: stream

        running: true
        command: ["media-control", "stream", "--no-diff", "--no-artwork", "--debounce=250"]

        stdout: SplitParser {
            onRead: line => {
                if (!line.trim().startsWith("{"))
                    return;
                try {
                    root.apply(JSON.parse(line));
                } catch (e) {
                // A truncated frame is not worth surfacing; the next one lands in 250ms.
                }
            }
        }

        onExited: restart.start()
    }

    Timer {
        id: restart

        interval: 3000
        onTriggered: stream.running = true
    }

    // The stream only emits on change, so ask once at startup to fill in
    // whatever was already playing.
    Process {
        running: true
        command: ["media-control", "get", "--no-artwork"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.apply(JSON.parse(text));
                } catch (e) {}
            }
        }
    }
}
