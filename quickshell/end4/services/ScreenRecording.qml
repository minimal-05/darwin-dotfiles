pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.modules.common
import Quickshell
import Quickshell.Io

/**
 * Whether scripts/videos/record.sh has a recording running.
 *
 * record.sh writes screencapture's pid to a file while it records and removes
 * it when it stops; this watches that file. The Linux original asked pgrep
 * every couple of seconds, which on macOS was the shell's steadiest idle spawn
 * for a state that changes twice per recording.
 *
 * The 30 s check only runs while a recording is believed to be in progress:
 * a screencapture that died without going through record.sh (killed from a
 * terminal, crashed) leaves the pidfile behind, and that is the one case the
 * file cannot report itself.
 */
Singleton {
    id: root

    // Same default as `qs` exports and record.sh falls back to.
    readonly property string pidFile: {
        const rt = Quickshell.env("XDG_RUNTIME_DIR");
        const base = (typeof rt === "string" && rt.length > 0) ? rt : "/tmp/quickshell-" + (Quickshell.env("UID") ?? "");
        return base + "/quickshell/recording.pid";
    }

    property bool recording: false
    property int pid: -1

    function apply(text: string): void {
        const n = parseInt(String(text ?? "").trim(), 10);
        root.pid = isNaN(n) ? -1 : n;
        root.recording = root.pid > 0;
    }

    FileView {
        id: pidView
        path: root.pidFile
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onTextChanged: root.apply(text())
        onLoadFailed: root.apply("")
    }

    Process {
        id: liveness
        command: ["/bin/kill", "-0", String(root.pid)]
        onExited: (code, status) => {
            if (code !== 0)
                root.apply("");
        }
    }

    Timer {
        interval: 30000
        repeat: true
        running: root.recording
        onTriggered: liveness.running = true
    }

    // record.sh flips the pidfile, which flips `recording`; nothing to set here.
    function recordFullscreen(): void {
        Quickshell.execDetached([Directories.recordScriptPath, "--fullscreen"]);
    }

    // Logical points of the global display space: what `screencapture -R`
    // wants and what yabai reports window frames in.
    function recordRegion(x, y, width, height): void {
        Quickshell.execDetached([Directories.recordScriptPath, "--region",
            `${Math.round(x)},${Math.round(y)} ${Math.round(width)}x${Math.round(height)}`]);
    }

    // record.sh with no arguments SIGINTs the running recording. A region
    // recording leaves the selector's outline up, so clear that too.
    function stop(): void {
        Quickshell.execDetached([Directories.recordScriptPath]);
        GlobalStates.regionSelectorOpen = false;
    }
}
