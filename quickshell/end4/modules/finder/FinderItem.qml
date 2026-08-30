import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * One row in the file list: type icon, name, size, modified date.
 */
Rectangle {
    id: root

    required property var modelData
    required property int index
    property bool selected: false
    property bool showSize: true
    property bool showDate: true

    readonly property string path: root.modelData.path
    readonly property bool isDir: root.modelData.isDir

    signal clicked
    signal activated
    signal contextRequested(real sx, real sy)

    function humanSize(bytes: real): string {
        if (bytes < 1024)
            return `${bytes} B`;
        const units = ["KB", "MB", "GB", "TB"];
        let value = bytes / 1024;
        let unit = 0;
        while (value >= 1024 && unit < units.length - 1) {
            value /= 1024;
            unit++;
        }
        return `${value < 10 ? value.toFixed(1) : Math.round(value)} ${units[unit]}`;
    }

    implicitHeight: 40
    radius: Appearance.rounding.small
    color: root.selected ? Appearance.colors.colSecondaryContainer : (mouseArea.containsMouse ? Appearance.colors.colLayer1Hover : "transparent")

    // Dragging out to another application. text/uri-list is the mime type Qt
    // hands to macOS as a file drag, so the drop lands wherever a Finder drag
    // would. Automatic means a real platform drag rather than a QML-internal one.
    Drag.dragType: Drag.Automatic
    Drag.supportedActions: Qt.CopyAction
    Drag.mimeData: ({
            "text/uri-list": "file://" + encodeURI(root.modelData.path)
        })

    Behavior on color {
        ColorAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 12
        spacing: 12

        MaterialSymbol {
            text: root.modelData.icon
            iconSize: Appearance.font.pixelSize.huge
            fill: root.isDir ? 1 : 0
            color: root.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colPrimary
        }

        StyledText {
            Layout.fillWidth: true
            text: root.modelData.name
            elide: Text.ElideMiddle
            color: root.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
        }

        StyledText {
            visible: root.showSize
            text: root.isDir ? "" : root.humanSize(root.modelData.size)
            horizontalAlignment: Text.AlignRight
            Layout.preferredWidth: 66
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
        }

        StyledText {
            visible: root.showDate
            text: Qt.formatDateTime(root.modelData.modified, "yyyy-MM-dd hh:mm")
            horizontalAlignment: Text.AlignRight
            Layout.preferredWidth: 112
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
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
            // A few pixels of slop so a shaky click stays a click.
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
                root.clicked();
                root.contextRequested(at.x, at.y);
                return;
            }
            if (!mouseArea.dragStarted)
                root.clicked();
        }
        onDoubleClicked: root.activated()
    }
}
