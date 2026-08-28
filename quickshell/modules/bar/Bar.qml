import QtQuick
import Quickshell
import qs.config
import qs.components
import qs.services

// The bar is a floating rounded panel inset from the screen edges, matching the
// SketchyBar layout it replaces: identity and app on the left, a measured-centre
// cluster around the space dots, control centre on the right.
PanelWindow {
    id: root

    required property var modelData

    screen: modelData
    color: "transparent"

    anchors {
        top: true
        left: true
        right: true
    }

    implicitHeight: Appearance.sizes.barHeight + Appearance.sizes.barMargin * 2

    Rectangle {
        id: surface

        anchors.fill: parent
        anchors.margins: Appearance.sizes.barMargin
        radius: Appearance.sizes.barRadius
        color: Appearance.colors.bar

        // Slides down from above the screen edge on load.
        y: Appearance.sizes.barMargin
        opacity: 0

        Component.onCompleted: {
            surface.opacity = 1;
            entrance.start();
        }

        NumberAnimation {
            id: entrance

            target: surface
            property: "y"
            from: -root.implicitHeight
            to: Appearance.sizes.barMargin
            duration: Appearance.anim.slow
            easing.type: Easing.OutBack
            easing.overshoot: 0.8
        }

        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.anim.spatial
            }
        }

        // ---------- left ----------
        Row {
            anchors.left: parent.left
            anchors.leftMargin: Appearance.sizes.padding
            anchors.verticalCenter: parent.verticalCenter
            spacing: Appearance.sizes.gap

            Pill {
                icon: ""
                iconFont: "Helvetica Neue"
                iconColor: Appearance.colors.primary
                onClicked: Spaces.missionControl()
            }

            Pill {
                visible: ActiveWindow.available
                text: ActiveWindow.appName
                textColor: Appearance.colors.primary
            }
        }

        // ---------- centre ----------
        Row {
            id: centre

            anchors.centerIn: parent
            spacing: Appearance.sizes.gap

            Pill {
                icon: "󰻠"
                iconColor: Sys.cpuColor
                text: `${Math.round(Sys.cpuUsage)}%`
            }

            Pill {
                icon: Net.icon
                iconColor: Appearance.colors.blue
                text: Net.formatRate(Net.downBytesPerSec)
            }

            SpaceDots {
                anchors.verticalCenter: parent.verticalCenter
            }

            Pill {
                icon: "󰥔"
                iconColor: Appearance.colors.tertiary
                text: clock.text
                textColor: Appearance.colors.tertiary

                SystemClock {
                    id: clock

                    property string text: Qt.formatDateTime(date, "ddd d MMM  H:mm")

                    precision: SystemClock.Minutes
                }
            }

            WeatherPill {}

            Pill {
                visible: Media.available
                icon: Media.icon
                iconColor: Appearance.colors.green
                text: Media.title.length > 28 ? Media.title.substring(0, 27) + "…" : Media.title
                onClicked: mouse => {
                    if (mouse.button === Qt.RightButton)
                        Media.next();
                    else
                        Media.playPause();
                }
                onScrolled: delta => delta > 0 ? Media.next() : Media.previous()
            }

            Pill {
                id: volumePill

                // Volume at the moment of the press, so a drag is absolute
                // rather than accumulating rounding error step by step.
                property int dragBase: 0

                icon: Audio.icon
                iconColor: Audio.muted ? Appearance.colors.red : Appearance.colors.secondary
                text: Audio.muted ? "muted" : `${Audio.volume}%`
                onClicked: Audio.toggleMute()
                onScrolled: delta => Audio.stepVolume(delta)
                onPressedChanged: {
                    if (volumePill.pressed)
                        volumePill.dragBase = Audio.volume;
                }
                // 2px per percent: a ~200px sweep covers the full range, which
                // is about the throw of the menubar slider.
                onDragged: dx => Audio.setVolume(volumePill.dragBase + dx / 2)

                // Hold to ramp, the way holding a volume key repeats. Which half
                // you hold picks the direction; releasing before the first tick
                // leaves it a plain click, so mute-on-click still works.
                Timer {
                    running: volumePill.pressed && !volumePill.dragging
                    repeat: true
                    interval: 350
                    onRunningChanged: if (running) interval = 350
                    onTriggered: {
                        interval = 80;
                        Audio.stepVolume(volumePill.pressedX > volumePill.width / 2 ? 120 : -120);
                    }
                }
            }

            Pill {
                visible: Bat.available
                icon: Bat.icon
                iconColor: {
                    if (Bat.charging)
                        return Appearance.colors.primary;
                    if (Bat.percentage <= 20)
                        return Appearance.colors.red;
                    if (Bat.percentage <= 40)
                        return Appearance.colors.yellow;
                    return Appearance.colors.green;
                }
                text: `${Bat.percentage}%`
            }
        }

        // ---------- right ----------
        Row {
            anchors.right: parent.right
            anchors.rightMargin: Appearance.sizes.padding
            anchors.verticalCenter: parent.verticalCenter
            spacing: Appearance.sizes.gap

            Pill {
                icon: "󰒓"
                iconColor: Appearance.colors.muted
            }
        }
    }
}
