import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
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

    // Navigation state lives here rather than in whatever hosts the view, so the
    // standalone app and any in-shell host share one implementation.
    property string currentPath: root.home
    property var backStack: []
    property var fwdStack: []
    property bool showHidden: false

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
        else if (root.imageExtensions.includes(ext) || ext === "svg")
            // The shell's own viewer rather than Preview.app, for the same
            // reason this window exists rather than a Finder one.
            Quickshell.execDetached(["qs-preview", path]);
        else
            Quickshell.execDetached(["open", path]);
    }

    // Escape leaves pick mode without choosing. The views do not accept it, so
    // it reaches this parent through the focus chain.
    Keys.onEscapePressed: event => {
        if (root.pickMode.length === 0)
            return;
        root.pickMode = "";
        event.accepted = true;
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
                // Only real raster images get a thumbnail; anything else would
                // mean a QuickLook subprocess per file.
                isImage: !isDir && root.imageExtensions.includes(ext),
            });
        }
        return out;
    }

    onEntriesChanged: {
        listView.currentIndex = root.entries.length > 0 ? 0 : -1;
        gridView.currentIndex = listView.currentIndex;
    }

    // Breakpoints. The window resizes down to a genuinely small size, so each
    // piece drops out at the width where it stops paying for its space: labels
    // first, then the date and size columns, then the sidebar itself.
    readonly property bool sidebarExpanded: root.width >= 720
    readonly property bool showSidebar: !root.sidebarHidden && root.width >= 470
    readonly property bool showSearch: root.width >= 560
    readonly property bool showSize: root.width >= 430
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

                    SidebarButton {}
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
                        selected: ListView.isCurrentItem
                        showSize: root.showSize
                        showDate: root.showDate
                        onClicked: listView.currentIndex = index
                        onActivated: root.activate(path, isDir)
                        onContextRequested: (sx, sy) => contextMenu.popup(sx, sy, modelData)
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
                    cellWidth: 108
                    cellHeight: 118
                    boundsBehavior: Flickable.DragOverBounds
                    model: root.gridMode ? root.entries : []

                    delegate: FinderTile {
                        width: gridView.cellWidth - 6
                        height: gridView.cellHeight - 6
                        selected: GridView.isCurrentItem
                        onClicked: gridView.currentIndex = index
                        onActivated: root.activate(path, isDir)
                        onContextRequested: (sx, sy) => contextMenu.popup(sx, sy, modelData)
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
