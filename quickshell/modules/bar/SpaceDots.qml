import QtQuick
import qs.config
import qs.services

// Space indicators. The focused space stretches into a filled pill; the rest
// stay as small dots. Widths animate, because an instant snap shifts the whole
// centre cluster mid-transition and reads as a hitch.
Row {
    id: root

    spacing: 6

    Repeater {
        model: Spaces.list

        Rectangle {
            id: dot

            required property var modelData

            readonly property bool focused: modelData.focused

            width: focused ? 34 : 14
            height: 10
            radius: 5
            color: focused ? Appearance.colors.primary : Appearance.colors.outline
            anchors.verticalCenter: parent.verticalCenter

            Behavior on width {
                NumberAnimation {
                    duration: Appearance.anim.spatial
                    easing.type: Easing.OutBack
                    easing.overshoot: 1.1
                }
            }

            Behavior on color {
                ColorAnimation {
                    duration: Appearance.anim.color
                    easing.type: Easing.OutCubic
                }
            }

            MouseArea {
                anchors.fill: parent
                anchors.margins: -4      // dots are small; give the pointer a real target
                acceptedButtons: Qt.LeftButton | Qt.RightButton

                onClicked: mouse => {
                    if (mouse.button === Qt.RightButton)
                        Spaces.missionControl();
                    else
                        Spaces.focus(dot.modelData.index);
                }

                onWheel: wheel => wheel.angleDelta.y > 0 ? Spaces.focusPrev() : Spaces.focusNext()
            }
        }
    }
}
