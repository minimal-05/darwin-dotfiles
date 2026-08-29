pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Whether a screen recording is running, and how to start or stop one.
 *
 * record.sh execs `screencapture -v`, and the bar button, the region selector
 * and a bare terminal can all start it, so the state is read back out of the
 * process table instead of being tracked at each call site.
 */
Singleton {
    id: root

    property bool recording: false

    // ponytail: a poll, not an event — screencapture publishes nothing to
    // subscribe to. If the lag before the stop button appears ever matters,
    // have record.sh touch a pidfile and put a FileView on it.
    Timer {
        running: true
        repeat: true
        interval: 2000
        triggeredOnStart: true
        onTriggered: if (!checkProc.running) checkProc.running = true
    }

    Process {
        id: checkProc
        // -v, not the bare name: a still capture is a `screencapture` process
        // too, and matching it turns the bar red every time you take a
        // screenshot.
        // Anchored (-fx) on the -v form: a still capture is a `screencapture`
        // process too, and an unanchored match also hits any shell or editor
        // whose own command line mentions the string.
        command: ["pgrep", "-fx", "(/[^ ]*)?/?screencapture -v.*"]
        onExited: (exitCode, exitStatus) => root.recording = (exitCode === 0)
    }

    // The flag is set optimistically so the stop button appears on the click
    // rather than up to a poll later; a start that fails is corrected by the
    // next tick.
    function recordFullscreen(): void {
        Quickshell.execDetached([Directories.recordScriptPath, "--fullscreen"]);
        root.recording = true;
    }

    // x/y/w/h in logical points of the global display space, which is what
    // `screencapture -R` wants and what yabai reports window frames in.
    function recordRegion(x, y, width, height): void {
        Quickshell.execDetached([Directories.recordScriptPath, "--region",
            `${Math.round(x)},${Math.round(y)} ${Math.round(width)}x${Math.round(height)}`]);
        root.recording = true;
    }

    // record.sh with no arguments is the toggle: it SIGINTs the running
    // screencapture, which is what finalises the movie file.
    function stop(): void {
        Quickshell.execDetached([Directories.recordScriptPath]);
        root.recording = false;
        // A region recording leaves the selector up in its post-selection phase,
        // drawing the outline of what is being recorded. Upstream clears that by
        // re-triggering the region action; stopping from the bar has to clear it
        // here or the outline is left on the screen with nothing behind it.
        GlobalStates.regionSelectorOpen = false;
    }
}
