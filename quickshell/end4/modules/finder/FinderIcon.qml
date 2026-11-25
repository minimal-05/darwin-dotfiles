import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * The picture for one entry, shared by list rows and icon tiles: a real
 * thumbnail for images, the real icon for apps, a QuickLook preview for
 * everything else it can render (video, pdf, documents), and the type glyph
 * as the fallback.
 */
Item {
    id: root

    required property var modelData
    property bool selected: false
    property int glyphSize: 56
    property int thumbSize: 128

    readonly property bool canPreview: !root.modelData.isDir && !root.modelData.isImage && !root.modelData.isApp
    // Keyed by path *and* mtime, so editing a file supersedes its preview
    // instead of showing a stale one forever.
    readonly property string previewPath: root.canPreview ? `${Directories.finderThumbs}/${Qt.md5(root.modelData.path + root.modelData.modified)}.png` : ""

    Image {
        id: thumbnail

        anchors.fill: parent
        visible: (root.modelData.isImage || root.modelData.isApp) && status === Image.Ready
        source: root.modelData.isImage ? `file://${root.modelData.path}` : root.modelData.isApp ? Quickshell.iconPath(root.modelData.path) : ""
        sourceSize.width: root.thumbSize
        sourceSize.height: root.thumbSize
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        cache: true
    }

    // QuickLook preview. qlmanage is the thumbnailer Finder itself uses, so a
    // .mov, a pdf or a Keynote deck all get a real preview without this shell
    // knowing any of those formats.
    Image {
        id: preview

        anchors.fill: parent
        visible: root.canPreview && status === Image.Ready
        source: previewProc.ready ? `file://${root.previewPath}` : ""
        sourceSize.width: root.thumbSize
        sourceSize.height: root.thumbSize
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        cache: true
    }

    // ponytail: one subprocess per file, so it is gated twice -- only for
    // delegates that exist (the views only build visible ones) and only after
    // one has held still for 200ms, so flinging through a big folder does not
    // spawn a process per row. The png is cached on disk and shared by both
    // views, so a file is only ever rendered once.
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
        iconSize: root.glyphSize
        fill: root.modelData.isDir ? 1 : 0
        color: root.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colPrimary
    }
}
