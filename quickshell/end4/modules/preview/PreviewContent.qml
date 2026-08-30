import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Qt.labs.folderlistmodel

/**
 * The image viewer. macOS hands a screenshot to Preview.app; this is the same
 * job in the shell's own Material styling, and it is deliberately only a viewer
 * -- Preview's markup tools are a whole second app and are one button away.
 */
Item {
    id: root

    property string path: ""
    signal closeRequested

    readonly property string fileName: root.path.split("/").pop()
    readonly property string directory: root.path.length > 0 ? FileUtils.parentDirectory(root.path) : ""

    readonly property list<string> imageExtensions: ["png", "jpg", "jpeg", "gif", "webp", "avif", "heic", "bmp", "tiff", "svg", "icns"]

    // Everything else in the folder, so the arrow keys walk a screenshot folder
    // the way Preview does.
    readonly property var siblings: {
        folderModel.count;
        folderModel.status;
        const out = [];
        for (let i = 0; i < folderModel.count; i++) {
            const p = FileUtils.trimFileProtocol(folderModel.get(i, "filePath"));
            if (root.imageExtensions.includes(p.split(".").pop().toLowerCase()))
                out.push(p);
        }
        return out;
    }
    readonly property int index: root.siblings.indexOf(root.path)

    // 0 means "whatever fits". Any other value is a zoom the user asked for, and
    // it survives moving to the next image on purpose -- flipping through a
    // folder at 200% is the point of holding a zoom.
    property real userZoom: 0
    readonly property real fitZoom: (image.implicitWidth > 0 && image.implicitHeight > 0) ? Math.min(view.width / image.implicitWidth, view.height / image.implicitHeight, 1) : 1
    readonly property real zoom: root.userZoom > 0 ? root.userZoom : root.fitZoom

    function open(path: string): void {
        root.path = path;
        root.userZoom = 0;
    }

    function step(delta: int): void {
        if (root.siblings.length === 0)
            return;
        const next = root.index + delta;
        if (next < 0 || next >= root.siblings.length)
            return;
        root.path = root.siblings[next];
    }

    function zoomBy(factor: real): void {
        root.userZoom = Math.max(0.05, Math.min(16, root.zoom * factor));
    }

    focus: true

    Keys.onPressed: event => {
        switch (event.key) {
        case Qt.Key_Escape:
            root.closeRequested();
            break;
        case Qt.Key_Left:
        case Qt.Key_Up:
            root.step(-1);
            break;
        case Qt.Key_Right:
        case Qt.Key_Down:
        case Qt.Key_Space:
            root.step(1);
            break;
        case Qt.Key_Plus:
        case Qt.Key_Equal:
            root.zoomBy(1.25);
            break;
        case Qt.Key_Minus:
            root.zoomBy(1 / 1.25);
            break;
        case Qt.Key_0:
            root.userZoom = 0;
            break;
        case Qt.Key_1:
            root.userZoom = 1;
            break;
        default:
            return;
        }
        event.accepted = true;
    }

    FolderListModel {
        id: folderModel

        folder: root.directory.length > 0 ? Qt.resolvedUrl(root.directory) : ""
        showDirs: false
        showHidden: false
        sortField: FolderListModel.Name
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 8

        Toolbar {
            Layout.fillWidth: true
            // Same shorter bar the file manager uses: this is the top edge of a
            // window, not a floating dock.
            implicitHeight: 44
            padding: 4
            enableShadow: false

            IconToolbarButton {
                text: "chevron_left"
                enabled: root.index > 0
                downAction: () => root.step(-1)

                StyledToolTip {
                    text: Translation.tr("Previous")
                }
            }

            IconToolbarButton {
                text: "chevron_right"
                enabled: root.index >= 0 && root.index < root.siblings.length - 1
                downAction: () => root.step(1)

                StyledToolTip {
                    text: Translation.tr("Next")
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 6
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: root.fileName
                    elide: Text.ElideMiddle
                    color: Appearance.colors.colOnLayer1
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.siblings.length > 1
                    text: `${root.index + 1} / ${root.siblings.length}`
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }

            IconToolbarButton {
                text: "zoom_out"
                downAction: () => root.zoomBy(1 / 1.25)

                StyledToolTip {
                    text: Translation.tr("Zoom out")
                }
            }

            StyledText {
                Layout.preferredWidth: 46
                horizontalAlignment: Text.AlignHCenter
                text: `${Math.round(root.zoom * 100)}%`
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }

            IconToolbarButton {
                text: "zoom_in"
                downAction: () => root.zoomBy(1.25)

                StyledToolTip {
                    text: Translation.tr("Zoom in")
                }
            }

            IconToolbarButton {
                text: "fit_screen"
                toggled: root.userZoom === 0
                downAction: () => root.userZoom = (root.userZoom === 0 ? 1 : 0)

                StyledToolTip {
                    text: root.userZoom === 0 ? Translation.tr("Actual size") : Translation.tr("Fit to window")
                }
            }

            // The way out for anything this viewer deliberately does not do --
            // markup, export, a format Qt cannot decode.
            IconToolbarButton {
                text: "open_in_new"
                downAction: () => Quickshell.execDetached(["open", "-a", "Preview", root.path])

                StyledToolTip {
                    text: Translation.tr("Open in Preview")
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Appearance.rounding.large
            color: Appearance.colors.colLayer1
            clip: true

            Flickable {
                id: view

                anchors.fill: parent
                contentWidth: Math.max(view.width, image.width)
                contentHeight: Math.max(view.height, image.height)
                boundsBehavior: Flickable.StopAtBounds
                interactive: image.width > view.width || image.height > view.height

                Image {
                    id: image

                    source: root.path.length > 0 ? `file://${encodeURI(root.path)}` : ""
                    width: implicitWidth * root.zoom
                    height: implicitHeight * root.zoom
                    x: Math.max(0, (view.contentWidth - width) / 2)
                    y: Math.max(0, (view.contentHeight - height) / 2)
                    // Full decode: this is the window you opened to look closely.
                    smooth: true
                    mipmap: true
                    asynchronous: true
                    cache: false
                }

                // Wheel is zoom rather than scroll -- panning is a drag, and an
                // image viewer that scrolls a picture that already fits is just
                // a window that will not sit still.
                WheelHandler {
                    onWheel: event => {
                        root.zoomBy(event.angleDelta.y > 0 ? 1.1 : 1 / 1.1);
                        event.accepted = true;
                    }
                }

                TapHandler {
                    onDoubleTapped: root.userZoom = (root.userZoom === 0 ? 1 : 0)
                }
            }

            MaterialLoadingIndicator {
                anchors.centerIn: parent
                visible: image.status === Image.Loading
            }

            StyledText {
                anchors.centerIn: parent
                visible: image.status === Image.Error || root.path.length === 0
                text: root.path.length === 0 ? Translation.tr("Nothing open") : Translation.tr("Cannot show this file")
                color: Appearance.colors.colSubtext
            }
        }
    }
}
