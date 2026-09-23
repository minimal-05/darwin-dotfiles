import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

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

    // Everything that is not already covered by a raster thumbnail or an app
    // icon -- pdfs, video, audio, office documents, source files -- can still
    // have a QuickLook preview.
    readonly property bool canPreview: !root.isDir && !root.modelData.isImage && !root.modelData.isApp
    // Keyed by path *and* mtime, so editing a file supersedes its preview
    // instead of showing a stale one forever.
    readonly property string previewPath: root.canPreview ? `${Directories.finderThumbs}/${Qt.md5(root.modelData.path + root.modelData.modified)}.png` : ""

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

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // Real thumbnails for images, the real icon for apps.
            // ponytail: no QuickLook previews for pdfs and video -- qlmanage is a
            // subprocess per file, and a folder of them would cost more than the
            // entire window does. Worth adding behind a cache if it's missed.
            Image {
                id: thumbnail

                anchors.fill: parent
                anchors.margins: 2
                visible: (root.modelData.isImage || root.modelData.isApp) && status === Image.Ready
                source: root.modelData.isImage ? `file://${root.modelData.path}` : root.modelData.isApp ? Quickshell.iconPath(root.modelData.path) : ""
                sourceSize.width: 128
                sourceSize.height: 128
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: true
            }

            // QuickLook preview. qlmanage is the thumbnailer Finder itself uses,
            // so a pdf, a video, a Keynote deck or a .c file all get a real
            // preview without this shell knowing any of those formats.
            Image {
                id: preview

                anchors.fill: parent
                anchors.margins: 2
                visible: root.canPreview && status === Image.Ready
                source: previewProc.ready ? `file://${root.previewPath}` : ""
                sourceSize.width: 128
                sourceSize.height: 128
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: true
            }

            // ponytail: one subprocess per file, so it is gated twice -- only
            // for tiles that exist (the GridView only builds visible ones) and
            // only after the tile has held still for 200ms, so flinging through
            // a big folder does not spawn a process per row. The png is cached
            // on disk, so a file is only ever rendered once.
            Timer {
                running: root.canPreview && !previewProc.ready
                interval: 200
                onTriggered: previewProc.running = true
            }

            Process {
                id: previewProc

                property bool ready: false
                command: ["bash", "-c", `out='${StringUtils.shellSingleQuoteEscape(root.previewPath)}'; `
                    + `[ -f "$out" ] && exit 0; `
                    + `mkdir -p '${StringUtils.shellSingleQuoteEscape(Directories.finderThumbs)}'; `
                    + `tmp=$(mktemp -d); `
                    + `qlmanage -t -s 256 -o "$tmp" '${StringUtils.shellSingleQuoteEscape(root.modelData.path)}' >/dev/null 2>&1; `
                    + `f=$(find "$tmp" -name '*.png' -maxdepth 1 | head -1); `
                    + `[ -n "$f" ] && mv "$f" "$out"; `
                    + `rm -rf "$tmp"; `
                    + `[ -f "$out" ]`]
                onExited: exitCode => previewProc.ready = (exitCode === 0)
            }

            MaterialSymbol {
                anchors.centerIn: parent
                visible: !thumbnail.visible && !preview.visible
                text: root.modelData.icon
                iconSize: 56
                fill: root.isDir ? 1 : 0
                color: root.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colPrimary
            }
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
