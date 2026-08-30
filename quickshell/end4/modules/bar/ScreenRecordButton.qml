pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick

/**
 * Bar button for screen recording.
 *
 * Idle: opens the picker, which dims the screen and puts the choice of what to
 * record in a toolbar near the bottom — see ScreenRecordOverlay. Recording: the
 * same spot in the bar turns into a red stop button, and clicking it ends the
 * recording.
 */
CircleUtilButton {
    id: root

    // Apple's system red rather than the palette's error colour: in a dark theme
    // m3error is a pale salmon, and a record indicator has one expected colour.
    readonly property color recordRed: Appearance.m3colors.darkmode ? "#ff453a" : "#ff3b30"

    colBackground: ScreenRecording.recording ? root.recordRed : "transparent"
    colBackgroundHover: ScreenRecording.recording ? Qt.lighter(root.recordRed, 1.15) : Appearance.colors.colLayer1Hover
    colRipple: ScreenRecording.recording ? Qt.darker(root.recordRed, 1.15) : Appearance.colors.colLayer1Active

    onClicked: {
        if (ScreenRecording.recording) {
            ScreenRecording.stop();
            return;
        }
        GlobalStates.screenRecordOverlayOpen = !GlobalStates.screenRecordOverlayOpen;
    }

    MaterialSymbol {
        horizontalAlignment: Qt.AlignHCenter
        fill: 1
        text: ScreenRecording.recording ? "stop" : "videocam"
        iconSize: Appearance.font.pixelSize.large
        color: ScreenRecording.recording ? "white" : Appearance.colors.colOnLayer2
    }
}
