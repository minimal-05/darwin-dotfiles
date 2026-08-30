import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * One tile in icon view: a thumbnail for images, the type glyph for everything
 * else, and the name underneath.
 */
Rectangle {
    id: root

    required property var modelData
    required property int index
    property bool selected: false

    readonly property string path: root.modelData.path
    readonly property bool isDir: root.modelData.isDir

    signal clicked
    signal activated
    signal contextRequested(real sx, real sy)

    radius: Appearance.rounding.small
    color: root.selected ? Appearance.colors.colSecondaryContainer : (mouseArea.containsMouse ? Appearance.colors.colLayer1Hover : "transparent")

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

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 6
        spacing: 4

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // Real thumbnails for images only.
            // ponytail: no QuickLook previews for pdfs and video -- qlmanage is a
            // subprocess per file, and a folder of them would cost more than the
            // entire window does. Worth adding behind a cache if it's missed.
            Image {
                id: thumbnail

                anchors.centerIn: parent
                width: Math.min(implicitWidth, parent.width)
                height: Math.min(implicitHeight, parent.height)
                visible: root.modelData.isImage && status === Image.Ready
                source: root.modelData.isImage ? `file://${root.modelData.path}` : ""
                sourceSize.width: 128
                sourceSize.height: 128
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: true
            }

            MaterialSymbol {
                anchors.centerIn: parent
                visible: !thumbnail.visible
                text: root.modelData.icon
                iconSize: 44
                fill: root.isDir ? 1 : 0
                color: root.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colPrimary
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.preferredHeight: 30
            text: root.modelData.name
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignTop
            wrapMode: Text.Wrap
            elide: Text.ElideMiddle
            maximumLineCount: 2
            font.pixelSize: Appearance.font.pixelSize.smaller
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
