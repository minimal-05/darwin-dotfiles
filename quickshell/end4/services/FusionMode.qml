pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs

/**
 * Fusion mode. Once Autodesk Fusion has been the frontmost app for 5 seconds,
 * yabai stops and the shell drops everything but screenshots, the lock screen
 * and the OSD (GlobalStates.fusionMode, read by PanelLoader). The next real app
 * to come to the front undoes both.
 *
 * The front app comes from `lsappinfo listen`, which streams LaunchServices'
 * own becameFrontmost notification -- no polling. Not ToplevelManager: that is
 * a yabai poll, and yabai is exactly what this turns off.
 */
Singleton {
    id: root

    readonly property string bundleId: "com.autodesk.fusion360"
    readonly property int dwell: 5000
    readonly property string yabai: "/opt/homebrew/bin/yabai"
    // Coming to the front without leaving Fusion: a screenshot selection and the
    // preview window are both this shell's own process.
    readonly property var ignored: ["org.quickshell.shell"]

    property bool engaged: false
    // Only restart yabai if this is what stopped it -- if it was already off,
    // leaving Fusion must not turn it on.
    // ponytail: in memory only, so a shell crash while engaged leaves yabai
    // stopped. Persist it to a state file if that ever happens in practice.
    property bool stoppedYabai: false

    function load(): void {}

    function frontChanged(bundle: string): void {
        if (bundle === root.bundleId) {
            if (!root.engaged && !dwellTimer.running)
                dwellTimer.start();
            return;
        }
        if (root.ignored.includes(bundle))
            return;
        dwellTimer.stop();
        if (root.engaged)
            root.disengage();
    }

    function engage(): void {
        root.engaged = true;
        GlobalStates.fusionMode = true;
        yabaiStop.running = true;
    }

    function disengage(): void {
        root.engaged = false;
        GlobalStates.fusionMode = false;
        if (root.stoppedYabai)
            Quickshell.execDetached([root.yabai, "--start-service"]);
        root.stoppedYabai = false;
    }

    // One notification per line. Spotlight and other UIElement apps come to
    // the front too, but nobody has switched away from Fusion by opening them.
    function parse(line: string): void {
        const id = /"CFBundleIdentifier"="([^"]*)"/.exec(line);
        const type = /"ApplicationType"="([^"]*)"/.exec(line);
        if (id && (!type || type[1] === "Foreground"))
            root.frontChanged(id[1]);
    }

    Timer {
        id: dwellTimer

        interval: root.dwell
        onTriggered: root.engage()
    }

    Process {
        id: yabaiStop

        command: ["sh", "-c", `pgrep -xq yabai && '${root.yabai}' --stop-service && echo stopped`]
        stdout: StdioCollector {
            onStreamFinished: root.stoppedYabai = this.text.includes("stopped")
        }
    }

    // Whatever is in front when the shell starts -- a reload while Fusion is
    // already up should still count it.
    Process {
        running: true
        command: ["sh", "-c", "lsappinfo info -only bundleid \"$(lsappinfo front)\""]
        stdout: StdioCollector {
            onStreamFinished: root.parse(this.text)
        }
    }

    Process {
        id: listener

        running: true
        command: ["lsappinfo", "listen", "+becameFrontmost", "forever"]
        stdout: SplitParser {
            onRead: line => root.parse(line)
        }
        // A dead listener would end Fusion mode detection silently.
        onExited: relisten.start()
    }

    Timer {
        id: relisten

        interval: 2000
        onTriggered: listener.running = true
    }

    IpcHandler {
        target: "fusionMode"

        // Manual override, and the way to try it without Fusion open.
        function toggle(): void {
            if (root.engaged)
                root.disengage();
            else
                root.engage();
        }
    }
}
