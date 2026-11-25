import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * One tile in icon view: a thumbnail for images and apps, the type glyph for
 * everything else, and the name underneath.
 */
Rectangle {
    id: root

    required property var modelData
    required property int index
    property bool selected: false
    // The paths a drag starting on this tile should carry -- the whole
    // selection when this tile is part of one, else just this tile.
    property var dragPaths: [modelData.path]

    readonly property string path: root.modelData.path
    readonly property bool isDir: root.modelData.isDir

    signal clicked(int modifiers)
    signal activated
    signal contextRequested(real sx, real sy)

    radius: Appearance.rounding.small
    color: root.selected ? Appearance.colors.colSecondaryContainer : (mouseArea.containsMouse ? Appearance.colors.colLayer1Hover : "transparent")

    Drag.dragType: Drag.Automatic
    Drag.supportedActions: Qt.CopyAction
    Drag.mimeData: ({
            "text/uri-list": root.dragPaths.map(p => "file://" + encodeURI(p)).join("\r\n")
        })

    Behavior on color {
        ColorAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 4
        spacing: 2

        FinderIcon {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 2
            modelData: root.modelData
            selected: root.selected
        }

        StyledText {
            Layout.fillWidth: true
            Layout.preferredHeight: 24
            text: root.modelData.name
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignTop
            wrapMode: Text.Wrap
            elide: Text.ElideMiddle
            maximumLineCount: 2
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: root.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
        }
    }

    MouseArea {
        id: mouseArea

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        property real pressX: 0
        property real pressY: 0
        property bool dragStarted: false

        onPressed: mouse => {
            mouseArea.pressX = mouse.x;
            mouseArea.pressY = mouse.y;
            mouseArea.dragStarted = false;
        }
        onPositionChanged: mouse => {
            if (!mouseArea.pressed || mouseArea.dragStarted)
                return;
            if (Math.abs(mouse.x - mouseArea.pressX) < 6 && Math.abs(mouse.y - mouseArea.pressY) < 6)
                return;
            mouseArea.dragStarted = true;
            // dragType Automatic turns this into a real platform drag as soon as
            // the attached object goes active; startDrag() is for Drag.None and
            // refuses to run before that.
            root.Drag.active = true;
        }
        onReleased: {
            root.Drag.active = false;
            mouseArea.dragStarted = false;
        }
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                // Scene coordinates: the menu overlay fills the window.
                const at = root.mapToItem(null, mouse.x, mouse.y);
                root.contextRequested(at.x, at.y);
                return;
            }
            if (!mouseArea.dragStarted)
                root.clicked(mouse.modifiers);
        }
        onDoubleClicked: root.activated()
    }
}
