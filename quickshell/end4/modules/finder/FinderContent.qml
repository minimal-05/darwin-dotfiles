import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel

Item {
    id: root

    property string query: ""
    property bool gridMode: false
    property bool sidebarHidden: false

    // Wallpaper pick mode. The shell's "Choose file" hands off to this window
    // instead of a native open panel, so activating an image reports it back
    // rather than opening it in Preview. Empty means the plain file manager.
    // Holds the light/dark mode the palette should be generated for.
    property string pickMode: ""
    signal picked(path: string)

    readonly property string home: FileUtils.trimFileProtocol(Directories.home).replace(/\/+$/, "")
    readonly property string wallpapersDir: `${root.place(Directories.pictures)}/Wallpapers`

    // Navigation state lives here rather than in whatever hosts the view, so the
    // standalone app and any in-shell host share one implementation. A picker
    // starts in the wallpapers folder -- Home would make you go find it
    // yourself every time you meant to just choose a wallpaper.
    property string currentPath: root.pickMode.length > 0 ? root.wallpapersDir : root.home
    property var backStack: []
    property var fwdStack: []
    property bool showHidden: false

    // Multi-selection. An ordered array of paths acting as a set, plus the
    // index a shift-click range extends from.
    property var selectedPaths: []
    property int selectionAnchor: -1

    function isSelected(path: string): bool {
        return root.selectedPaths.includes(path);
    }

    function selectOnly(index: int): void {
        root.selectionAnchor = index;
        const e = root.entries[index];
        root.selectedPaths = e ? [e.path] : [];
    }

    function toggleSelect(index: int): void {
        root.selectionAnchor = index;
        const e = root.entries[index];
        if (!e)
            return;
        root.selectedPaths = root.selectedPaths.includes(e.path) ? root.selectedPaths.filter(p => p !== e.path) : [...root.selectedPaths, e.path];
    }

    function selectRange(index: int): void {
        if (root.selectionAnchor < 0) {
            root.selectOnly(index);
            return;
        }
        const lo = Math.min(root.selectionAnchor, index);
        const hi = Math.max(root.selectionAnchor, index);
        root.selectedPaths = root.entries.slice(lo, hi + 1).map(e => e.path);
    }

    function clearSelection(): void {
        root.selectedPaths = [];
        root.selectionAnchor = -1;
    }

    // The one place that turns a click's modifier keys into a selection change,
    // so list and grid delegates only have to report what was pressed.
    function selectFromClick(index: int, modifiers: int): void {
        if (modifiers & Qt.ShiftModifier)
            root.selectRange(index);
        else if (modifiers & Qt.ControlModifier) // Command on macOS -- Qt swaps the names.
            root.toggleSelect(index);
        else
            root.selectOnly(index);
    }

    function place(path: string): string {
        return FileUtils.trimFileProtocol(path).replace(/\/+$/, "");
    }

    function navigate(path: string): void {
        const target = path.replace(/\/+$/, "") || "/";
        if (target === root.currentPath)
            return;
        root.backStack = [...root.backStack, root.currentPath];
        root.fwdStack = [];
        root.currentPath = target;
    }

    function goBack(): void {
        if (root.backStack.length === 0)
            return;
        root.fwdStack = [...root.fwdStack, root.currentPath];
        root.currentPath = root.backStack[root.backStack.length - 1];
        root.backStack = root.backStack.slice(0, -1);
    }

    function goForward(): void {
        if (root.fwdStack.length === 0)
            return;
        root.backStack = [...root.backStack, root.currentPath];
        root.currentPath = root.fwdStack[root.fwdStack.length - 1];
        root.fwdStack = root.fwdStack.slice(0, -1);
    }

    function goUp(): void {
        root.navigate(root.currentPath.replace(/\/[^/]*$/, "") || "/");
    }

    // Directories open in place. Everything else is handed to `open`, which
    // already knows what macOS has registered for a file type -- including .app
    // bundles, which are directories but must be launched, not browsed.
    function activate(path: string, isDir: bool): void {
        const ext = path.split(".").pop().toLowerCase();
        if (isDir && !path.endsWith(".app"))
            root.navigate(path);
        else if (root.pickMode.length > 0 && root.imageExtensions.includes(ext))
            root.picked(path);
        else if (root.imageExtensions.includes(ext) || ["svg", "pdf", "mp4", "mov", "m4v"].includes(ext))
            // The shell's own viewer rather than Preview.app or QuickTime, for
            // the same reason this window exists rather than a Finder one.
            Quickshell.execDetached(["qs-preview", path]);
        else
            Quickshell.execDetached(["open", path]);
    }

    // Escape backs out one level at a time: cancel a pick, else drop the
    // selection. The views do not accept it, so it reaches this parent through
    // the focus chain.
    Keys.onEscapePressed: event => {
        if (root.pickMode.length > 0) {
            root.pickMode = "";
            event.accepted = true;
        } else if (root.selectedPaths.length > 0) {
            root.clearSelection();
            event.accepted = true;
        }
    }

    Shortcut {
        sequences: [StandardKey.SelectAll]
        onActivated: {
            root.selectedPaths = root.entries.map(e => e.path);
            root.selectionAnchor = root.entries.length - 1;
        }
    }

    readonly property var imageExtensions: ["png", "jpg", "jpeg", "gif", "webp", "heic", "bmp", "tiff", "icns"]

    // Material Symbols rather than a freedesktop icon theme: macOS has no icon
    // theme installed, and the shell already ships the symbol font.
    function iconFor(name: string, isDir: bool): string {
        if (name.endsWith(".app"))
            return "apps";
        if (isDir)
            return "folder";
        const ext = name.split(".").pop().toLowerCase();
        if (root.imageExtensions.includes(ext) || ext === "svg")
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

    // The word shown in the list's Type column. Mirrors iconFor's buckets so the
    // glyph and the word can never disagree, and falls back to "<EXT> file" the
    // way Finder does for anything it has no name for.
    function typeFor(name: string, isDir: bool): string {
        if (name.endsWith(".app"))
            return Translation.tr("Application");
        if (isDir)
            return Translation.tr("Folder");
        const dot = name.lastIndexOf(".");
        if (dot <= 0)
            return Translation.tr("Document");
        const ext = name.slice(dot + 1).toLowerCase();
        const kind = (root.imageExtensions.includes(ext) || ext === "svg") ? Translation.tr("%1 image")
            : ["mp4", "mov", "mkv", "webm", "avi", "m4v"].includes(ext) ? Translation.tr("%1 video")
            : ["mp3", "flac", "wav", "m4a", "aac", "ogg", "opus"].includes(ext) ? Translation.tr("%1 audio")
            : ["zip", "tar", "gz", "bz2", "xz", "7z", "rar", "dmg"].includes(ext) ? Translation.tr("%1 archive")
            : ext === "pdf" ? Translation.tr("%1 document")
            : Translation.tr("%1 file");
        return kind.arg(ext.toUpperCase());
    }

    readonly property var places: [
        {
            name: Translation.tr("Home"),
            path: root.home,
            icon: "home"
        },
        {
            name: Translation.tr("Desktop"),
            path: `${root.home}/Desktop`,
            icon: "desktop_windows"
        },
        {
            name: Translation.tr("Documents"),
            path: root.place(Directories.documents),
            icon: "description"
        },
        {
            name: Translation.tr("Downloads"),
            path: root.place(Directories.downloads),
            icon: "download"
        },
        {
            name: Translation.tr("Pictures"),
            path: root.place(Directories.pictures),
            icon: "image"
        },
        {
            name: Translation.tr("Music"),
            path: root.place(Directories.music),
            icon: "music_note"
        },
        {
            name: Translation.tr("Movies"),
            path: root.place(Directories.videos),
            icon: "movie"
        },
        {
            name: Translation.tr("Applications"),
            path: "/Applications",
            icon: "apps"
        },
        // Listing it needs Full Disk Access for Files.app -- ~/.Trash is
        // TCC-protected, and without the grant it just reads as empty.
        {
            name: Translation.tr("Trash"),
            path: `${root.home}/.Trash`,
            icon: "delete"
        },
    ]

    FolderListModel {
        id: folderModel

        folder: `file://${root.currentPath}`
        showDirsFirst: true
        showHidden: root.showHidden
        sortField: FolderListModel.Name
        caseSensitive: false
    }

    // One shape for both sidebar sections: a place, or a mounted volume.
    component SidebarButton: RippleButton {
        id: placeButton

        required property var modelData

        Layout.fillWidth: true
        implicitHeight: 38
        buttonRadius: Appearance.rounding.full
        toggled: root.currentPath === placeButton.modelData.path
        colBackgroundToggled: Appearance.colors.colSecondaryContainer
        colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
        colRippleToggled: Appearance.colors.colSecondaryContainerActive
        downAction: () => root.navigate(placeButton.modelData.path)
        // Right-click the Trash to empty it. Finder does the work, so it needs
        // no disk access and asks for confirmation the way Finder always does.
        altAction: placeButton.modelData.path === `${root.home}/.Trash` ? () => Quickshell.execDetached(["osascript", "-e", 'tell application "Finder" to empty trash']) : null

        StyledToolTip {
            text: placeButton.modelData.name
            // Only worth showing once the label is gone.
            extraVisibleCondition: !root.sidebarExpanded
        }

        contentItem: RowLayout {
            spacing: 10

            MaterialSymbol {
                Layout.leftMargin: root.sidebarExpanded ? 8 : 0
                Layout.fillWidth: !root.sidebarExpanded
                horizontalAlignment: Text.AlignHCenter
                text: placeButton.modelData.icon
                iconSize: Appearance.font.pixelSize.larger
                fill: placeButton.toggled ? 1 : 0
                color: placeButton.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
            }

            StyledText {
                visible: root.sidebarExpanded
                Layout.fillWidth: true
                text: placeButton.modelData.name
                elide: Text.ElideRight
                color: placeButton.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
            }
        }
    }

    FolderListModel {
        id: volumeModel

        folder: "file:///Volumes"
        showFiles: false
        showDirs: true
        showHidden: false
        sortField: FolderListModel.Name
    }

    // Everything mounted, including the boot disk -- macOS keeps a "Macintosh HD"
    // symlink in /Volumes alongside any external drive, so one model covers both.
    readonly property var volumes: {
        volumeModel.count;
        volumeModel.status;
        const out = [];
        for (let i = 0; i < volumeModel.count; i++) {
            out.push({
                name: volumeModel.get(i, "fileName"),
                path: volumeModel.get(i, "filePath"),
                icon: "hard_drive"
            });
        }
        return out;
    }

    // What can be ejected: real directories in /Volumes. The boot disk is a
    // symlink to /, and find does not follow symlinks by default, so that
    // leaves it out. Re-run whenever something mounts or unmounts.
    property var ejectable: []

    Connections {
        target: volumeModel
        function onCountChanged() {
            ejectableProc.running = true;
        }
    }

    Process {
        id: ejectableProc

        running: true
        command: ["find", "/Volumes", "-mindepth", "1", "-maxdepth", "1", "-type", "d"]
        stdout: StdioCollector {
            onStreamFinished: root.ejectable = this.text.split("\n").filter(l => l.length > 0)
        }
    }

    // ponytail: fire and forget -- a busy disk just stays mounted with no
    // message. Wire diskutil's stderr into a notification if that bites.
    function eject(path: string): void {
        if (root.currentPath === path || root.currentPath.startsWith(path + "/"))
            root.navigate(root.home);
        Quickshell.execDetached(["diskutil", "eject", path]);
    }

    // FolderListModel's own nameFilters only ever filter *files* -- directories
    // come through whatever the pattern is -- so the search box cannot use them
    // and filters here instead.
    // ponytail: rebuilds the whole array whenever the folder changes, which is
    // nothing for a directory you'd actually sit and browse. If this ever gets
    // pointed at tens of thousands of files, put a proper proxy model behind it.
    readonly property var entries: {
        folderModel.count; // dependencies, so this re-runs as the folder loads
        folderModel.status;
        const needle = root.query.toLowerCase();
        const out = [];
        for (let i = 0; i < folderModel.count; i++) {
            const name = folderModel.get(i, "fileName");
            if (needle.length > 0 && !name.toLowerCase().includes(needle))
                continue;
            const isDir = folderModel.get(i, "fileIsDir");
            const ext = name.split(".").pop().toLowerCase();
            out.push({
                name: name,
                path: folderModel.get(i, "filePath"),
                isDir: isDir,
                size: folderModel.get(i, "fileSize"),
                modified: folderModel.get(i, "fileModified"),
                icon: root.iconFor(name, isDir),
                type: root.typeFor(name, isDir),
                // Only real raster images get a thumbnail; anything else would
                // mean a QuickLook subprocess per file.
                isImage: !isDir && root.imageExtensions.includes(ext),
                isApp: name.endsWith(".app"),
            });
        }
        return out;
    }

    onEntriesChanged: {
        listView.currentIndex = root.entries.length > 0 ? 0 : -1;
        gridView.currentIndex = listView.currentIndex;
        root.clearSelection();
    }

    // Breakpoints. The window resizes down to a genuinely small size, so each
    // piece drops out at the width where it stops paying for its space: labels
    // first, then the date and size columns, then the sidebar itself.
    readonly property bool sidebarExpanded: root.width >= 720
    readonly property bool showSidebar: !root.sidebarHidden && root.width >= 470
    readonly property bool showSearch: root.width >= 560
    readonly property bool showSize: root.width >= 430
    readonly property bool showType: root.width >= 520
    readonly property bool showDate: root.width >= 610

    RowLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 8

        // Places. Collapses to an icon rail, then drops out entirely -- the
        // breadcrumb and the up button still navigate without it.
        Rectangle {
            visible: root.showSidebar
            Layout.preferredWidth: root.sidebarExpanded ? 196 : 50
            Layout.fillHeight: true
            radius: Appearance.rounding.large
            color: Appearance.colors.colLayer1

            Behavior on Layout.preferredWidth {
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 6
                spacing: 2

                Repeater {
                    model: root.places

                    SidebarButton {}
                }

                // Volumes, only once something is mounted.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    Layout.bottomMargin: 4
                    Layout.leftMargin: 8
                    Layout.rightMargin: 8
                    visible: root.volumes.length > 0
                    implicitHeight: 1
                    color: Appearance.colors.colLayer0Border
                }

                Repeater {
                    model: root.volumes

                    RowLayout {
                        id: volumeRow

                        required property var modelData

                        Layout.fillWidth: true
                        spacing: 0

                        SidebarButton {
                            modelData: volumeRow.modelData
                        }

                        IconToolbarButton {
                            visible: root.sidebarExpanded && root.ejectable.includes(volumeRow.modelData.path)
                            implicitHeight: 32
                            text: "eject"
                            downAction: () => root.eject(volumeRow.modelData.path)

                            StyledToolTip {
                                text: Translation.tr("Eject")
                            }
                        }
                    }
                }

                Item {
                    Layout.fillHeight: true
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 8

            // Only thing that says this window is picking rather than browsing.
            Rectangle {
                Layout.fillWidth: true
                visible: root.pickMode.length > 0
                implicitHeight: 36
                radius: Appearance.rounding.small
                color: Appearance.colors.colSecondaryContainer

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 4
                    spacing: 8

                    MaterialSymbol {
                        text: "wallpaper"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnSecondaryContainer
                    }

                    StyledText {
                        Layout.fillWidth: true
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnSecondaryContainer
                        elide: Text.ElideRight
                        text: Translation.tr("Open an image to use it as your wallpaper")
                    }

                    IconToolbarButton {
                        text: "close"
                        downAction: () => root.pickMode = ""

                        StyledToolTip {
                            text: Translation.tr("Cancel")
                        }
                    }
                }
            }

            Toolbar {
                Layout.fillWidth: true
                // Shorter than the stock 56: this is the top edge of a window,
                // not a floating dock, and the height was mostly dead space.
                implicitHeight: 44
                padding: 4
                // The drop shadow is a shader effect compiled on first paint,
                // and this window is already slow enough to appear.
                enableShadow: false

                IconToolbarButton {
                    text: "arrow_back"
                    enabled: root.backStack.length > 0
                    downAction: () => root.goBack()

                    StyledToolTip {
                        text: Translation.tr("Back")
                    }
                }

                IconToolbarButton {
                    text: "arrow_forward"
                    enabled: root.fwdStack.length > 0
                    downAction: () => root.goForward()

                    StyledToolTip {
                        text: Translation.tr("Forward")
                    }
                }

                AddressBar {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    // Its breadcrumb is a ListView, so the address bar's implicit
                    // width counts the buttons and nothing else. Without a floor it
                    // shrinks to just those and the path disappears completely as
                    // the window narrows.
                    Layout.minimumWidth: 130
                    padding: 3
                    radius: Appearance.rounding.full
                    directory: root.currentPath
                    onNavigateToDirectory: dir => root.navigate(dir)
                }

                ToolbarTextField {
                    visible: root.showSearch
                    // Give up width before the path does.
                    implicitWidth: 165
                    Layout.minimumWidth: 90
                    placeholderText: Translation.tr("Search")
                    text: root.query
                    onTextChanged: root.query = text
                }

                IconToolbarButton {
                    text: root.sidebarHidden ? "left_panel_open" : "left_panel_close"
                    toggled: root.sidebarHidden
                    downAction: () => root.sidebarHidden = !root.sidebarHidden

                    StyledToolTip {
                        text: root.sidebarHidden ? Translation.tr("Show sidebar") : Translation.tr("Hide sidebar")
                    }
                }

                IconToolbarButton {
                    text: root.gridMode ? "view_list" : "grid_view"
                    downAction: () => root.gridMode = !root.gridMode

                    StyledToolTip {
                        text: root.gridMode ? Translation.tr("List view") : Translation.tr("Icon view")
                    }
                }

                IconToolbarButton {
                    text: root.showHidden ? "visibility" : "visibility_off"
                    toggled: root.showHidden
                    downAction: () => root.showHidden = !root.showHidden

                    StyledToolTip {
                        text: Translation.tr("Show hidden files")
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer1

                // Both views exist, but the hidden one is given an empty model so
                // it holds no delegates and costs nothing to keep around.
                StyledListView {
                    id: listView

                    anchors.fill: parent
                    anchors.margins: 6
                    clip: true
                    visible: !root.gridMode
                    focus: !root.gridMode
                    spacing: 1
                    model: root.gridMode ? [] : root.entries

                    delegate: FinderItem {
                        width: listView.width
                        selected: root.isSelected(modelData.path)
                        showSize: root.showSize
                        showType: root.showType
                        showDate: root.showDate
                        dragPaths: root.isSelected(modelData.path) && root.selectedPaths.length > 1 ? root.selectedPaths : [modelData.path]
                        onClicked: modifiers => {
                            listView.currentIndex = index;
                            root.selectFromClick(index, modifiers);
                        }
                        onActivated: root.activate(path, isDir)
                        onContextRequested: (sx, sy) => {
                            listView.currentIndex = index;
                            if (!root.isSelected(modelData.path))
                                root.selectOnly(index);
                            contextMenu.popup(sx, sy, root.entries.filter(e => root.isSelected(e.path)));
                        }
                    }

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            const entry = root.entries[listView.currentIndex];
                            if (entry)
                                root.activate(entry.path, entry.isDir);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Backspace) {
                            root.goUp();
                            event.accepted = true;
                        }
                    }
                }

                GridView {
                    id: gridView

                    anchors.fill: parent
                    anchors.margins: 6
                    clip: true
                    visible: root.gridMode
                    focus: root.gridMode
                    // As many ~108px columns as fit, then stretched to share
                    // out the leftover so there is no dead gutter on the right.
                    cellWidth: gridView.width / Math.max(1, Math.floor(gridView.width / 108))
                    cellHeight: gridView.cellWidth + 10
                    boundsBehavior: Flickable.DragOverBounds
                    model: root.gridMode ? root.entries : []

                    delegate: FinderTile {
                        width: gridView.cellWidth - 6
                        height: gridView.cellHeight - 6
                        selected: root.isSelected(modelData.path)
                        dragPaths: root.isSelected(modelData.path) && root.selectedPaths.length > 1 ? root.selectedPaths : [modelData.path]
                        onClicked: modifiers => {
                            gridView.currentIndex = index;
                            root.selectFromClick(index, modifiers);
                        }
                        onActivated: root.activate(path, isDir)
                        onContextRequested: (sx, sy) => {
                            gridView.currentIndex = index;
                            if (!root.isSelected(modelData.path))
                                root.selectOnly(index);
                            contextMenu.popup(sx, sy, root.entries.filter(e => root.isSelected(e.path)));
                        }
                    }

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            const entry = root.entries[gridView.currentIndex];
                            if (entry)
                                root.activate(entry.path, entry.isDir);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Backspace) {
                            root.goUp();
                            event.accepted = true;
                        }
                    }
                }

                StyledText {
                    anchors.centerIn: parent
                    visible: root.entries.length === 0
                    text: root.query.length > 0 ? Translation.tr("Nothing matches") : Translation.tr("Empty folder")
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }

    FinderContextMenu {
        id: contextMenu

        anchors.fill: parent
        finder: root
    }
}
