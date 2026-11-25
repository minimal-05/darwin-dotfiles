import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

DockButton {
    id: root
    property var appToplevel
    property var appListRoot
    property int lastFocused: -1
    property real iconSize: 35
    property real countDotWidth: 10
    property real countDotHeight: 4
    property bool appIsActive: appToplevel.toplevels.find(t => (t.activated == true)) !== undefined

    readonly property bool isSeparator: appToplevel.appId === "SEPARATOR"
    readonly property bool isDragSource: appListRoot.draggingAppId !== "" && appListRoot.draggingAppId === appToplevel.appId
    readonly property bool isDropTarget: appListRoot.draggingAppId !== "" && !root.isDragSource && appListRoot.dragHoverAppId === appToplevel.appId
    property var desktopEntry: AppSearch.lookup(appToplevel.appId)
    // The entry's icon is the app bundle's own path, which NSWorkspace always
    // resolves. guessIcon is for a window whose app qs-index-apps never saw.
    readonly property string iconName: root.desktopEntry?.icon ?? AppSearch.guessIcon(appToplevel.appId)
    enabled: !isSeparator
    implicitWidth: isSeparator ? 1 : implicitHeight - topInset - bottomInset
    opacity: root.isDragSource ? 0.4 : 1

    // Drag an icon onto a pinned one to pin/reorder it there; drag a pinned
    // icon onto a running one -- the "regular section" -- to unpin it. Same
    // gesture as the real macOS Dock. dragThreshold keeps a plain click from
    // ever registering as a drag.
    DragHandler {
        id: dragHandler
        target: null
        enabled: !root.isSeparator
        dragThreshold: 12
        onActiveChanged: {
            if (active) appListRoot.dragStart(root.appToplevel.appId);
            else appListRoot.dragEnd();
        }
        onCentroidChanged: {
            if (active) appListRoot.dragMove(root, centroid.position.x, centroid.position.y);
        }
    }

    Connections {
        target: DesktopEntries

        function onApplicationsChanged() {
            root.desktopEntry = AppSearch.lookup(appToplevel.appId);
        }
    }

    Loader {
        active: isSeparator
        anchors {
            fill: parent
            topMargin: dockVisualBackground.margin + dockRow.padding + Appearance.rounding.normal
            bottomMargin: dockVisualBackground.margin + dockRow.padding + Appearance.rounding.normal
        }
        sourceComponent: DockSeparator {}
    }

    Loader {
        anchors.fill: parent
        active: appToplevel.toplevels.length > 0
        sourceComponent: MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            onEntered: {
                appListRoot.lastHoveredButton = root
                appListRoot.buttonHovered = true
                lastFocused = appToplevel.toplevels.length - 1
            }
            onExited: {
                if (appListRoot.lastHoveredButton === root) {
                    appListRoot.buttonHovered = false
                }
            }
        }
    }

    onClicked: {
        if (appToplevel.toplevels.length === 0) {
            root.desktopEntry?.execute();
            return;
        }
        lastFocused = (lastFocused + 1) % appToplevel.toplevels.length
        appToplevel.toplevels[lastFocused].activate()
    }

    middleClickAction: () => {
        root.desktopEntry?.execute();
    }

    // ponytail: right-click used to pin and unpin outright, which is one item
    // of a real dock menu and not the one anybody reaches for. Pinning is still
    // here, one row down, under its macOS name.
    altAction: () => {
        appListRoot.openMenu(root);
    }

    contentItem: Loader {
        active: !isSeparator
        sourceComponent: Item {
            anchors.centerIn: parent

            // A line in the gap before this icon, not a highlight on it: reorder()
            // always inserts the dragged icon just before whatever isDropTarget
            // names, so the line marks the actual landing spot rather than
            // pointing at the icon being passed over.
            Rectangle {
                visible: root.isDropTarget
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.leftMargin: -6
                width: 2
                radius: 1
                color: Appearance.colors.colPrimary
            }

            Loader {
                id: iconImageLoader
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }
                active: !root.isSeparator
                // An appId that names no installed app -- a pin left behind by
                // an uninstall, or one carried over from a Linux config --
                // reaches guessIcon's last resort, "application-x-executable",
                // which is an XDG theme name NSWorkspace has never heard of. The
                // "image-missing" fallback then drew a broken picture that never
                // resolved into anything. A glyph reads as "no icon" rather than
                // as a rendering fault.
                sourceComponent: AppSearch.iconExists(root.iconName) ? appIcon : missingIcon
            }

            Component {
                id: appIcon
                IconImage {
                    source: Quickshell.iconPath(root.iconName)
                    implicitSize: root.iconSize
                }
            }

            Component {
                id: missingIcon
                MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter
                    text: "web_asset_off"
                    iconSize: root.iconSize
                    color: Appearance.colors.colOnLayer0
                }
            }

            Loader {
                active: Config.options.dock.monochromeIcons
                anchors.fill: iconImageLoader
                sourceComponent: Item {
                    Desaturate {
                        id: desaturatedIcon
                        visible: false // There's already color overlay
                        anchors.fill: parent
                        source: iconImageLoader
                        desaturation: 0.8
                    }
                    ColorOverlay {
                        anchors.fill: desaturatedIcon
                        source: desaturatedIcon
                        color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.9)
                    }
                }
            }

            RowLayout {
                spacing: 3
                anchors {
                    top: iconImageLoader.bottom
                    topMargin: 2
                    horizontalCenter: parent.horizontalCenter
                }
                Repeater {
                    model: Math.min(appToplevel.toplevels.length, 3)
                    delegate: Rectangle {
                        required property int index
                        radius: Appearance.rounding.full
                        implicitWidth: (appToplevel.toplevels.length <= 3) ? 
                            root.countDotWidth : root.countDotHeight // Circles when too many
                        implicitHeight: root.countDotHeight
                        color: appIsActive ? Appearance.colors.colPrimary : ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.4)
                    }
                }
            }
        }
    }
}
