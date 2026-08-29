import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * Right-click menu over the file list, plus the rename prompt it opens.
 *
 * Every action shells out to the tool macOS already ships for the job rather
 * than reimplementing it -- `open -R` for reveal, qlmanage for Quick Look,
 * ditto for zipping, and Finder itself (over AppleScript) for the trash, so
 * deletions land in the real Trash and stay undoable.
 */
Item {
    id: root

    required property var finder

    property var target: null
    property bool menuOpen: false
    property bool renameOpen: false
    property real menuX: 0
    property real menuY: 0

    readonly property string targetPath: root.target ? root.target.path : ""
    readonly property string targetName: root.target ? root.target.name : ""
    readonly property string targetDir: root.target && root.target.isDir ? root.target.path : root.targetPath.replace(/\/[^/]*$/, "")

    visible: root.menuOpen || root.renameOpen

    function popup(x: real, y: real, entry: var): void {
        root.target = entry;
        root.menuX = x;
        root.menuY = y;
        root.menuOpen = true;
    }

    function close(): void {
        root.menuOpen = false;
    }

    function run(args: var): void {
        Quickshell.execDetached(args);
        root.close();
    }

    // AppleScript string literals escape the same way JSON does, which saves
    // hand-rolling quoting for paths with spaces or quotes in them.
    function trash(): void {
        root.run(["osascript", "-e", `tell application "Finder" to delete POSIX file ${JSON.stringify(root.targetPath)}`]);
    }

    function duplicatePath(): string {
        const dot = root.targetName.lastIndexOf(".");
        if (root.target.isDir || dot <= 0)
            return `${root.targetPath} copy`;
        const stem = root.targetPath.slice(0, root.targetPath.length - (root.targetName.length - dot));
        return `${stem} copy${root.targetName.slice(dot)}`;
    }

    // Click anywhere else to dismiss.
    MouseArea {
        anchors.fill: parent
        enabled: root.menuOpen
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: root.close()
    }

    component MenuEntry: Rectangle {
        id: entry

        property string label: ""
        property string icon: ""
        property bool danger: false
        signal triggered

        Layout.fillWidth: true
        implicitHeight: 32
        radius: Appearance.rounding.small
        color: entryArea.containsMouse ? Appearance.colors.colLayer2Hover : "transparent"

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 12
            spacing: 10

            MaterialSymbol {
                text: entry.icon
                iconSize: Appearance.font.pixelSize.large
                color: entry.danger ? Appearance.m3colors.m3error : Appearance.colors.colOnLayer2
            }

            StyledText {
                Layout.fillWidth: true
                text: entry.label
                color: entry.danger ? Appearance.m3colors.m3error : Appearance.colors.colOnLayer2
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
        }

        MouseArea {
            id: entryArea

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: entry.triggered()
        }
    }

    Rectangle {
        id: menu

        visible: root.menuOpen
        // Keep the whole menu on screen no matter which corner was clicked.
        x: Math.max(6, Math.min(root.menuX, root.width - width - 6))
        y: Math.max(6, Math.min(root.menuY, root.height - height - 6))
        width: 232
        implicitHeight: menuColumn.implicitHeight + 12
        height: implicitHeight
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer2
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        ColumnLayout {
            id: menuColumn

            anchors.fill: parent
            anchors.margins: 6
            spacing: 1

            MenuEntry {
                label: Translation.tr("Open")
                icon: "open_in_new"
                onTriggered: {
                    root.finder.activate(root.targetPath, root.target.isDir);
                    root.close();
                }
            }

            MenuEntry {
                label: Translation.tr("Quick Look")
                icon: "visibility"
                onTriggered: root.run(["qlmanage", "-p", root.targetPath])
            }

            MenuEntry {
                label: Translation.tr("Show in Finder")
                icon: "folder_open"
                onTriggered: root.run(["open", "-R", root.targetPath])
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 3
                Layout.bottomMargin: 3
                implicitHeight: 1
                color: Appearance.colors.colLayer0Border
            }

            MenuEntry {
                label: Translation.tr("Rename")
                icon: "edit"
                onTriggered: {
                    root.menuOpen = false;
                    renameField.text = root.targetName;
                    root.renameOpen = true;
                    renameField.forceActiveFocus();
                    renameField.selectAll();
                }
            }

            MenuEntry {
                label: Translation.tr("Duplicate")
                icon: "content_copy"
                onTriggered: root.run(["cp", "-R", root.targetPath, root.duplicatePath()])
            }

            MenuEntry {
                label: Translation.tr("Compress")
                icon: "folder_zip"
                onTriggered: root.run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", root.targetPath, `${root.targetPath}.zip`])
            }

            MenuEntry {
                label: Translation.tr("Copy path")
                icon: "link"
                onTriggered: {
                    Quickshell.clipboardText = root.targetPath;
                    root.close();
                }
            }

            MenuEntry {
                label: Translation.tr("Open terminal here")
                icon: "terminal"
                onTriggered: root.run(["open", "-na", "kitty", "--args", "--directory", root.targetDir])
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 3
                Layout.bottomMargin: 3
                implicitHeight: 1
                color: Appearance.colors.colLayer0Border
            }

            MenuEntry {
                label: Translation.tr("Move to Trash")
                icon: "delete"
                danger: true
                onTriggered: root.trash()
            }
        }
    }

    // Rename prompt. A scrim so a stray click cannot leave it half-dismissed.
    Rectangle {
        visible: root.renameOpen
        anchors.fill: parent
        color: Appearance.m3colors.m3scrim
        opacity: 0.4

        MouseArea {
            anchors.fill: parent
            onClicked: root.renameOpen = false
        }
    }

    Rectangle {
        id: renameDialog

        visible: root.renameOpen
        anchors.centerIn: parent
        width: Math.min(360, root.width - 40)
        implicitHeight: renameColumn.implicitHeight + 32
        height: implicitHeight
        radius: Appearance.rounding.large
        color: Appearance.colors.colLayer2

        ColumnLayout {
            id: renameColumn

            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            StyledText {
                text: Translation.tr("Rename")
                color: Appearance.colors.colOnLayer2
                font.pixelSize: Appearance.font.pixelSize.large
            }

            MaterialTextField {
                id: renameField

                Layout.fillWidth: true
                onAccepted: renameDialog.commit()
            }

            RowLayout {
                Layout.alignment: Qt.AlignRight
                spacing: 8

                DialogButton {
                    buttonText: Translation.tr("Cancel")
                    onClicked: root.renameOpen = false
                }

                DialogButton {
                    buttonText: Translation.tr("Rename")
                    onClicked: renameDialog.commit()
                }
            }
        }

        function commit(): void {
            const name = renameField.text.trim();
            // A name with a slash in it would silently mean "move somewhere else".
            if (name.length === 0 || name === root.targetName || name.includes("/")) {
                root.renameOpen = false;
                return;
            }
            const parent = root.targetPath.replace(/\/[^/]*$/, "");
            Quickshell.execDetached(["mv", root.targetPath, `${parent}/${name}`]);
            root.renameOpen = false;
        }
    }
}
