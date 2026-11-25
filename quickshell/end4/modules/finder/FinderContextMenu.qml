import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * Right-click menu over the file list, plus the rename prompt it opens.
 * `targets` is always an array -- one entry for a plain right-click, several
 * when it lands on an existing multi-selection.
 *
 * Every action shells out to the tool macOS already ships for the job rather
 * than reimplementing it -- `open -R` for reveal, qlmanage for Quick Look,
 * ditto/zip for archiving, and Finder itself (over AppleScript) for the trash,
 * so deletions land in the real Trash and stay undoable.
 */
Item {
    id: root

    required property var finder

    property var targets: []
    property bool menuOpen: false
    property bool renameOpen: false
    property real menuX: 0
    property real menuY: 0

    readonly property int count: root.targets.length
    readonly property string targetName: root.count === 1 ? root.targets[0].name : ""
    // "Open terminal here" and the multi-file compress destination both need one
    // folder to act in: the item itself when it is the sole selected directory,
    // else the folder the selection lives in -- which is simply the one open in
    // the window, since a context menu only ever fires on what that shows.
    // Everything selected sits directly in the Trash: offer Put Back instead
    // of trashing it a second time.
    readonly property bool inTrash: root.count > 0 && root.targets.every(t => t.path.replace(/\/[^/]*$/, "") === `${root.finder.home}/.Trash`)
    readonly property string primaryDir: root.count === 1 && root.targets[0].isDir ? root.targets[0].path : root.finder.currentPath

    visible: root.menuOpen || root.renameOpen

    function popup(x: real, y: real, entries: var): void {
        root.targets = entries;
        root.menuX = x;
        root.menuY = y;
        root.menuOpen = true;
    }

    function close(): void {
        root.menuOpen = false;
    }

    function run(command: var): void {
        Quickshell.execDetached(command);
        root.close();
    }

    function runIn(command: var, dir: string): void {
        Quickshell.execDetached({
            command: command,
            workingDirectory: dir
        });
        root.close();
    }

    // Through Finder, so deletions land in the real Trash and stay undoable --
    // put-back.py does the delete and notes where each item came from, which is
    // what Put Back reads.
    function trash(): void {
        root.run(["python3", "-E", "-S", Directories.putBackScriptPath, "--trash", ...root.targets.map(t => t.path)]);
    }

    function duplicatePathFor(entry: var): string {
        const dot = entry.name.lastIndexOf(".");
        if (entry.isDir || dot <= 0)
            return `${entry.path} copy`;
        const stem = entry.path.slice(0, entry.path.length - (entry.name.length - dot));
        return `${stem} copy${entry.name.slice(dot)}`;
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
        color: entryArea.containsMouse ? Appearance.m3colors.m3surfaceContainerHighest : "transparent"

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
        // Opaque on purpose. colLayer2 already carries the theme's content
        // transparency, and the file list showing through made it unreadable.
        color: Appearance.m3colors.m3surfaceContainerHigh
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        ColumnLayout {
            id: menuColumn

            anchors.fill: parent
            anchors.margins: 6
            spacing: 1

            MenuEntry {
                visible: root.inTrash
                label: Translation.tr("Put Back")
                icon: "restore_from_trash"
                onTriggered: root.run(["python3", "-E", "-S", Directories.putBackScriptPath, ...root.targets.map(t => t.path)])
            }

            MenuEntry {
                label: root.count > 1 ? Translation.tr("Open %1 items").arg(root.count) : Translation.tr("Open")
                icon: "open_in_new"
                onTriggered: {
                    root.targets.forEach(t => root.finder.activate(t.path, t.isDir));
                    root.close();
                }
            }

            MenuEntry {
                label: Translation.tr("Quick Look")
                icon: "visibility"
                onTriggered: root.run(["qlmanage", "-p", ...root.targets.map(t => t.path)])
            }

            MenuEntry {
                label: Translation.tr("Show in Finder")
                icon: "folder_open"
                onTriggered: root.run(["open", "-R", ...root.targets.map(t => t.path)])
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 3
                Layout.bottomMargin: 3
                implicitHeight: 1
                color: Appearance.colors.colLayer0Border
            }

            MenuEntry {
                visible: root.count === 1
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
                onTriggered: {
                    root.targets.forEach(t => Quickshell.execDetached(["cp", "-R", t.path, root.duplicatePathFor(t)]));
                    root.close();
                }
            }

            MenuEntry {
                label: Translation.tr("Compress")
                icon: "folder_zip"
                onTriggered: {
                    if (root.count === 1) {
                        const t = root.targets[0];
                        root.run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", t.path, `${t.path}.zip`]);
                        return;
                    }
                    // ditto's archive mode only ever takes one source; zip takes
                    // several, which is what Finder's own "Compress N items" does
                    // under the hood. Run with cwd set to the shared folder so the
                    // archive holds plain names instead of this machine's full paths.
                    root.runIn(["zip", "-rq", "--", "Archive.zip", ...root.targets.map(t => t.name)], root.primaryDir);
                }
            }

            MenuEntry {
                label: Translation.tr("Copy path")
                icon: "link"
                onTriggered: {
                    Quickshell.clipboardText = root.targets.map(t => t.path).join("\n");
                    root.close();
                }
            }

            MenuEntry {
                visible: root.count > 0 && root.targets.every(t => root.finder.ejectable.includes(t.path))
                label: Translation.tr("Eject")
                icon: "eject"
                onTriggered: {
                    root.targets.forEach(t => root.finder.eject(t.path));
                    root.close();
                }
            }

            MenuEntry {
                label: Translation.tr("Open terminal here")
                icon: "terminal"
                onTriggered: root.run(["open", "-na", "kitty", "--args", "--directory", root.primaryDir])
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 3
                Layout.bottomMargin: 3
                implicitHeight: 1
                color: Appearance.colors.colLayer0Border
            }

            MenuEntry {
                visible: !root.inTrash
                label: root.count > 1 ? Translation.tr("Move %1 items to Trash").arg(root.count) : Translation.tr("Move to Trash")
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
            if (root.count !== 1) {
                root.renameOpen = false;
                return;
            }
            const name = renameField.text.trim();
            const target = root.targets[0];
            // A name with a slash in it would silently mean "move somewhere else".
            if (name.length === 0 || name === target.name || name.includes("/")) {
                root.renameOpen = false;
                return;
            }
            const parent = target.path.replace(/\/[^/]*$/, "");
            Quickshell.execDetached(["mv", target.path, `${parent}/${name}`]);
            root.renameOpen = false;
        }
    }
}
