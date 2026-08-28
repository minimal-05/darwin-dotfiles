import QtQuick
import qs.config

// The bar's one structural primitive: an icon, an optional label, and a
// background that reacts to hover. Everything in the bar is one of these.
Rectangle {
    id: root

    property string icon: ""
    property string text: ""
    property color iconColor: Appearance.colors.surfaceFg
    property color textColor: Appearance.colors.surfaceFg

    // Overridable because the Apple logo only exists in Apple's own fonts.
    property string iconFont: Appearance.font.icon
    property bool interactive: true
    property bool filled: true

    signal clicked(var mouse)
    signal scrolled(int delta)
    // Horizontal pixels moved since the press, while the button is held.
    signal dragged(real dx)

    readonly property alias pressed: area.pressed
    readonly property alias dragging: area.dragging
    // Where in the pill the press landed, so a consumer can act on which half.
    readonly property alias pressedX: area.pressX

    implicitWidth: row.implicitWidth + Appearance.sizes.padding * 2
    implicitHeight: Appearance.sizes.pillHeight
    radius: Appearance.sizes.pillRadius

    color: {
        if (!filled)
            return "transparent";
        return area.containsMouse && interactive ? Appearance.colors.hover : Appearance.colors.pill;
    }

    Behavior on color {
        ColorAnimation {
            duration: Appearance.anim.color
            easing.type: Easing.OutCubic
        }
    }

    Row {
        id: row

        anchors.centerIn: parent
        spacing: root.icon && root.text ? 6 : 0

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.icon.length > 0
            text: root.icon
            color: root.iconColor
            font.family: root.iconFont
            font.pixelSize: Appearance.font.iconSize

            Behavior on color {
                ColorAnimation {
                    duration: Appearance.anim.color
                    easing.type: Easing.OutCubic
                }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.text.length > 0
            text: root.text
            color: root.textColor
            font.family: Appearance.font.sans
            font.pixelSize: Appearance.font.normal
            font.weight: Font.Medium
        }
    }

    MouseArea {
        id: area

        anchors.fill: parent
        hoverEnabled: root.interactive
        enabled: root.interactive
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        property real pressX: 0
        property bool dragging: false

        onPressed: mouse => {
            area.pressX = mouse.x;
            area.dragging = false;
        }
        onPositionChanged: mouse => {
            // hoverEnabled means this also fires with no button down.
            if (!area.pressed)
                return;
            const dx = mouse.x - area.pressX;
            // ponytail: 4px of slop so a slightly shaky click stays a click.
            if (!area.dragging && Math.abs(dx) < 4)
                return;
            area.dragging = true;
            root.dragged(dx);
        }
        onClicked: mouse => {
            if (!area.dragging)
                root.clicked(mouse);
        }
        onWheel: wheel => root.scrolled(wheel.angleDelta.y)
    }
}
