pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Output volume and device. AppleScript drives the system volume without any
// permission prompt; SwitchAudioSource names and switches the output device.
//
// This is the honest subset of what Quickshell.Services.Pipewire exposes on
// Linux: there is no node/link graph and no per-application volume here.
Singleton {
    id: root

    property int volume: 0            // 0-100
    property bool muted: false
    property string deviceName: ""
    property list<string> devices: []
    property double lastChange: 0

    readonly property string icon: {
        if (muted || volume === 0)
            return "󰝟";
        if (volume < 34)
            return "󰕿";
        if (volume < 67)
            return "󰖀";
        return "󰕾";
    }

    // Not `int`: callers pass fractional notch positions, and QML truncates a
    // real on the way into an int parameter, which would bias every step down.
    function setVolume(value: real): void {
        const clamped = Math.max(0, Math.min(100, Math.round(value)));
        if (clamped === root.volume)
            return;
        root.volume = clamped;
        root.lastChange = Date.now();
        // macOS unmutes as soon as you move the volume, by key or by slider.
        if (root.muted)
            root.toggleMute();
        // Each osascript spawn costs ~90ms, far slower than a scroll burst or a
        // drag emits. Push the latest value on a timer instead of firing one
        // process per event, which would drop writes and rubber-band the value.
        pusher.restart();
    }

    // macOS moves output volume in 1/16 notches (6.25 points), which is what the
    // F11/F12 keys and the menubar slider land on. Snap to the same grid so our
    // steps match the system's instead of drifting off it.
    readonly property real notch: 100 / 16

    // Wheel deltas are in eighths of a degree; 120 is one physical detent, which
    // is worth exactly one notch. Scaling by that rather than gating on it keeps
    // a trackpad's stream of small deltas moving the volume immediately instead
    // of sitting in a dead zone until they add up.
    property real subPoint: 0

    function stepVolume(delta: real): void {
        const amount = delta / 120 * root.notch + root.subPoint;
        const whole = Math.trunc(amount);
        // Carry the leftover fraction so slow scrolling still accumulates.
        root.subPoint = amount - whole;
        if (whole !== 0)
            root.setVolume(root.volume + whole);
    }

    function toggleMute(): void {
        root.muted = !root.muted;
        root.lastChange = Date.now();
        muter.exec(["osascript", "-e", `set volume output muted ${root.muted}`]);
    }

    function setDevice(name: string): void {
        switcher.exec(["SwitchAudioSource", "-s", name]);
        refresh();
    }

    function refresh(): void {
        stateProc.running = true;
        deviceProc.running = true;
    }

    Process {
        id: setter
    }

    Process {
        id: muter
    }

    Timer {
        id: pusher

        interval: 50
        onTriggered: setter.exec(["osascript", "-e", `set volume output volume ${root.volume}`])
    }

    Process {
        id: switcher
    }

    Process {
        id: stateProc

        running: true
        command: ["osascript", "-e", "set s to (get volume settings)\nreturn (output volume of s as string) & \",\" & (output muted of s as string)"]

        stdout: StdioCollector {
            onStreamFinished: {
                // A read in flight during our own write returns the stale value.
                if (Date.now() - root.lastChange < 1500)
                    return;
                const parts = text.trim().split(",");
                if (parts.length < 2)
                    return;
                const vol = parseInt(parts[0], 10);
                if (!isNaN(vol))
                    root.volume = vol;
                root.muted = parts[1].trim() === "true";
            }
        }
    }

    Process {
        id: deviceProc

        running: true
        command: ["SwitchAudioSource", "-c"]

        stdout: StdioCollector {
            onStreamFinished: root.deviceName = text.trim()
        }
    }

    Process {
        id: deviceListProc

        command: ["SwitchAudioSource", "-a", "-t", "output"]

        stdout: StdioCollector {
            onStreamFinished: root.devices = text.trim().split("\n").filter(l => l.length > 0)
        }
    }

    function refreshDevices(): void {
        deviceListProc.running = true;
    }

    // Nothing pushes volume changes to us, so poll. Cheap, and slow enough that
    // dragging our own slider never fights the poller.
    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }
}
