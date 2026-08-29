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

    // Material Symbols rather than a freedesktop icon theme: macOS has no icon
    // theme installed, and the shell already ships the symbol font.
    readonly property string icon: {
        if (root.modelData.name.endsWith(".app"))
            return "apps";
        if (root.isDir)
            return "folder";
        const ext = root.modelData.name.split(".").pop().toLowerCase();
        if (["png", "jpg", "jpeg", "gif", "webp", "heic", "svg", "bmp", "tiff", "icns"].includes(ext))
            return "image";
        if (["mp4", "mov", "mkv", "webm", "avi", "m4v"].includes(ext))
            return "movie";
        if (["mp3", "flac", "wav", "m4a", "aac", "ogg", "opus"].includes(ext))
            return "music_note";
        if (["zip", "tar", "gz", "bz2", "xz", "7z", "rar", "dmg"].includes(ext))
            return "folder_zip";
        if (ext === "pdf")
            return "picture_as_pdf";
        if (["js", "ts", "py", "qml", "c", "cpp", "h", "hpp", "rs", "go", "sh", "json", "yml", "yaml", "toml", "html", "css", "swift", "java", "rb", "lua", "nix"].includes(ext))
            return "code_blocks";
        if (["txt", "md", "rtf", "log"].includes(ext))
            return "description";
        return "draft";
    }

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
            text: root.icon
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

        onClicked: root.clicked()
        onDoubleClicked: root.activated()
    }
}
