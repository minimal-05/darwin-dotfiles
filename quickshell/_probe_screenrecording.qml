// Probe for services/ScreenRecording.qml: `recording` follows the pidfile
// scripts/videos/record.sh writes, with no pgrep in between.
//
//   bin/qs-test <this> --binary ... -- screenrecording state     "recording <pid>" or "idle"
//   bin/qs-test <this> --binary ... -- screenrecording pidfile   the path being watched

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

ShellRoot {
    IpcHandler {
        target: "screenrecording"

        function state(): string {
            return ScreenRecording.recording ? ("recording " + ScreenRecording.pid) : "idle";
        }

        function pidfile(): string {
            return ScreenRecording.pidFile;
        }
    }
}
