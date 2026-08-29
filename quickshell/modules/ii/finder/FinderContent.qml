import qs
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

    // Navigation state lives here rather than in whatever hosts the view, so the
    // standalone app and any in-shell host share one implementation.
    property string currentPath: root.home
    property var backStack: []
    property var fwdStack: []
    property bool showHidden: false

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
        if (isDir && !path.endsWith(".app"))
            root.navigate(path);
        else
            Quickshell.execDetached(["open", path]);
    }

    readonly property string home: FileUtils.trimFileProtocol(Directories.home).replace(/\/+$/, "")

    function place(path: string): string {
        return FileUtils.trimFileProtocol(path).replace(/\/+$/, "");
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
            out.push({
                name: name,
                path: folderModel.get(i, "filePath"),
                isDir: folderModel.get(i, "fileIsDir"),
                size: folderModel.get(i, "fileSize"),
                modified: folderModel.get(i, "fileModified"),
            });
        }
        return out;
    }

    onEntriesChanged: listView.currentIndex = root.entries.length > 0 ? 0 : -1

    // Breakpoints. The window resizes down to a genuinely small size, so each
    // piece drops out at the width where it stops paying for its space: labels
    // first, then the date and size columns, then the sidebar itself.
    readonly property bool sidebarExpanded: root.width >= 720
    readonly property bool showSidebar: root.width >= 470
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

                    RippleButton {
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

            Toolbar {
                Layout.fillWidth: true
                // Shorter than the stock 56: this is the top edge of a window,
                // not a floating dock, and the height was mostly dead space.
                implicitHeight: 44
                padding: 4

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

                StyledListView {
                    id: listView

                    anchors.fill: parent
                    anchors.margins: 6
                    clip: true
                    focus: true
                    spacing: 1
                    model: root.entries

                    delegate: FinderItem {
                        width: listView.width
                        selected: ListView.isCurrentItem
                        showSize: root.showSize
                        showDate: root.showDate
                        onClicked: listView.currentIndex = index
                        onActivated: root.activate(path, isDir)
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

                StyledText {
                    anchors.centerIn: parent
                    visible: root.entries.length === 0
                    text: root.query.length > 0 ? Translation.tr("Nothing matches") : Translation.tr("Empty folder")
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }
}
