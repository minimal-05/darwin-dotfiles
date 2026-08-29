//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1

// A small, self-contained bar. This is the "other" config: it shares nothing
// with end4/ except the binary that runs it, which is the point -- it exists to
// be edited without touching 950 files of somebody else's shell.
//
//   qs -c mine
//
// ponytail: one file on purpose. Split it when a second panel needs the same
// widget, not before.

import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root

    // Everything the bar draws, polled in one place and refreshed by the single
    // timer below rather than by a timer each -- one wakeup for the whole bar.
    property string appName: ""
    property int battery: -1
    property bool charging: false
    property int volume: -1

    readonly property color bg: "#e61e1e2e"
    readonly property color fg: "#cdd6f4"
    readonly property color dim: "#9399b2"
    readonly property int barHeight: 28

    // yabai already runs here for tiling, so it is the cheapest source for the
    // focused window. Filter on `has-focus` rather than taking the first result:
    // the window list is not ordered by focus.
    Process {
        id: appProc
        command: ["sh", "-c", "yabai -m query --windows 2>/dev/null | jq -r 'map(select(.\"has-focus\")) | .[0].app // \"\"'"]
        stdout: StdioCollector {
            onStreamFinished: root.appName = this.text.trim()
        }
    }

    // ioreg, not `pmset -g batt`: pmset prints prose that has changed between
    // releases, ioreg gives the numbers directly.
    Process {
        id: battProc
        command: ["sh", "-c", "ioreg -rn AppleSmartBattery | awk '/\"CurrentCapacity\"/{c=$3} /\"MaxCapacity\"/{m=$3} /\"IsCharging\"/{s=$3} END{if(m>0) printf \"%d %s\\n\", c*100/m, s}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = this.text.trim().split(" ");
                if (parts.length === 2) {
                    root.battery = parseInt(parts[0]);
                    root.charging = parts[1] === "Yes";
                }
            }
        }
    }

    Process {
        id: volProc
        command: ["osascript", "-e", "output volume of (get volume settings)"]
        stdout: StdioCollector {
            onStreamFinished: root.volume = parseInt(this.text.trim())
        }
    }

    // 2s is fast enough to feel live for an app name, slow enough that three
    // subprocesses a tick cost nothing measurable.
    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            appProc.running = true;
            battProc.running = true;
            volProc.running = true;
        }
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property var modelData
            screen: modelData

            anchors {
                top: true
                left: true
                right: true
            }
            implicitHeight: root.barHeight
            color: "transparent"

            Rectangle {
                anchors.fill: parent
                color: root.bg

                Text {
                    anchors {
                        left: parent.left
                        leftMargin: 12
                        verticalCenter: parent.verticalCenter
                    }
                    width: Math.min(implicitWidth, parent.width / 3)
                    text: root.appName
                    color: root.fg
                    font.pixelSize: 12
                    font.bold: true
                    elide: Text.ElideRight
                }

                Text {
                    anchors.centerIn: parent
                    text: Qt.formatDateTime(clock.date, "ddd d MMM  HH:mm")
                    color: root.fg
                    font.pixelSize: 12
                }

                Row {
                    anchors {
                        right: parent.right
                        rightMargin: 12
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: 12

                    Text {
                        text: root.volume < 0 ? "" : (root.volume === 0 ? "muted" : `vol ${root.volume}`)
                        color: root.dim
                        font.pixelSize: 12
                    }

                    Text {
                        text: root.battery < 0 ? "" : `${root.charging ? "⚡" : ""}${root.battery}%`
                        // Red below 20% and not charging -- the only state worth
                        // colouring, so it stays a signal rather than decoration.
                        color: (root.battery < 20 && !root.charging) ? "#f38ba8" : root.dim
                        font.pixelSize: 12
                    }
                }
            }
        }
    }
}
