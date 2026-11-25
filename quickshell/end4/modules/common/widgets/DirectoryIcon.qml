import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

// From https://github.com/caelestia-dots/shell with modifications.
// License: GPLv3
//
// macOS has no freedesktop icon theme, so the icon names this used to resolve
// ("inode-directory", "image-missing", the mime name of a file) all missed and
// Quickshell.iconPath handed back its magenta not-found placeholder -- every
// folder in the wallpaper picker rendered as a pink square. Material symbols are
// what the rest of this shell draws with and they are always present, so folders
// and non-images use a glyph and only real images load as images.
Item {
    id: root
    required property var fileModelData

    readonly property bool isDir: root.fileModelData.fileIsDir
    // Set by the mime probe below for files that turn out to be images.
    property bool isImage: false

    StyledImage {
        id: image
        anchors.fill: parent
        visible: !root.isDir && root.isImage && status === Image.Ready
        asynchronous: true
        fillMode: Image.PreserveAspectFit
        source: (!root.isDir && root.isImage) ? root.fileModelData.fileUrl : ""
    }

    MaterialSymbol {
        anchors.centerIn: parent
        visible: !image.visible
        text: root.isDir ? "folder" : "draft"
        fill: root.isDir ? 1 : 0
        iconSize: Math.max(24, Math.min(parent.width, parent.height) * 0.5)
        color: Appearance.colors.colPrimary
    }

    Process {
        running: !root.isDir
        command: ["file", "--mime", "-b", root.fileModelData.filePath]
        stdout: StdioCollector {
            onStreamFinished: {
                const mime = text.split(";")[0].trim().replace("/", "-");
                root.isImage = Images.validImageTypes.some(t => mime === `image-${t}`);
            }
        }
    }
}
