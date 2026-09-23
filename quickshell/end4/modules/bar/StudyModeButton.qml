import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * Bar entry for study mode: a glyph that turns into a countdown while a session
 * is running. Clicking it only ever opens the confirmation -- it cannot start,
 * and once a session is live it cannot stop one either.
 */
Item {
    id: root

    implicitWidth: row.implicitWidth + 12
    implicitHeight: Appearance.sizes.baseBarHeight

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 4

        MaterialSymbol {
            text: "school"
            iconSize: Appearance.font.pixelSize.larger
            fill: StudyMode.active ? 1 : 0
            color: StudyMode.active ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
        }

        StyledText {
            visible: StudyMode.active
            text: StudyMode.remainingText
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colPrimary
        }
    }

    // "+N XP" floats up out of the icon every time the watcher pays out.
    StyledText {
        id: xpFloat
        anchors.horizontalCenter: parent.horizontalCenter
        y: 10
        opacity: 0
        font.pixelSize: Appearance.font.pixelSize.smaller
        font.weight: Font.Bold
        color: Appearance.colors.colPrimary
        SequentialAnimation {
            id: xpAnim
            PropertyAction { target: xpFloat; property: "opacity"; value: 1 }
            PropertyAction { target: xpFloat; property: "y"; value: 16 }
            ParallelAnimation {
                NumberAnimation { target: xpFloat; property: "y"; to: -2; duration: 1200; easing.type: Easing.OutCubic }
                NumberAnimation { target: xpFloat; property: "opacity"; to: 0; duration: 1200; easing.type: Easing.InQuad }
            }
        }
        Connections {
            target: StudyMode
            function onGained(xp): void {
                xpFloat.text = `+${xp} XP`;
                xpAnim.restart();
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        // No stop path on purpose: ending early is a terminal errand. Left click
        // while idle asks to start; otherwise (or right click) opens the tracker.
        onClicked: mouse => {
            if (mouse.button === Qt.LeftButton && !StudyMode.active)
                GlobalStates.studyModeConfirmOpen = true;
            else
                GlobalStates.studyTrackerOpen = !GlobalStates.studyTrackerOpen;
        }

        // StyledToolTip falls back to "always shown" when its parent has no
        // `hovered` -- and a MouseArea does not, so this was pinned under the
        // bar permanently. Drive it off containsMouse explicitly instead.
        StyledToolTip {
            extraVisibleCondition: false
            alternativeVisibleCondition: mouseArea.containsMouse && !StudyMode.active
                && !GlobalStates.studyModeConfirmOpen && !GlobalStates.studyTrackerOpen
            text: Translation.tr("Study · right-click for your stats (⌃⌥⌘S)")
        }
    }
}
