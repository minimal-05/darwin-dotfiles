import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland

LazyLoader {
    id: root

    property Item hoverTarget
    default property Item contentItem
    property real popupBackgroundMargin: 0

    // Opt in for a popup that is clicked into rather than only read (the app
    // menus). The pointer has to leave hoverTarget to reach the rows, so
    // hovering the popup counts too; the whole window is hit-testable so there
    // is no dead strip between the bar and the card; and closing waits out two
    // pointer polls (POINTER_POLL_MS is 50 in src/cocoa/panel_window.cpp) so
    // crossing that edge cannot drop it for a frame. Off by default: the
    // read-only popups close the instant the pointer leaves the bar, as before.
    property bool interactive: false
    property int closeGrace: 100
    readonly property bool contentHovered: interactive && (root.item?.contentHovered ?? false)
    readonly property bool wanted: (hoverTarget && hoverTarget.containsMouse) || contentHovered
    property bool held: false
    onWantedChanged: {
        if (!interactive) return;
        if (wanted) held = true;
        // No window up (a region selection has it closed): nothing to cross
        // into, so let go at once rather than leaving `held` set to bring the
        // popup back on its own when the selection ends.
        else if (!root.item) held = false;
    }

    // A snip overlay covers the screen but cannot take the pointer: hover here
    // is polled, so without this the bar's popups open straight through it --
    // into the shot, and over the selection.
    active: (interactive ? held : (hoverTarget && hoverTarget.containsMouse)) && !GlobalStates.regionSelectorOpen

    component: PanelWindow {
        id: popupWindow
        color: "transparent"

        property bool contentHovered: contentHover.hovered

        anchors.left: !Config.options.bar.vertical || (Config.options.bar.vertical && !Config.options.bar.bottom)
        anchors.right: Config.options.bar.vertical && Config.options.bar.bottom
        anchors.top: Config.options.bar.vertical || (!Config.options.bar.vertical && !Config.options.bar.bottom)
        anchors.bottom: !Config.options.bar.vertical && Config.options.bar.bottom

        implicitWidth: popupBackground.implicitWidth + Appearance.sizes.elevationMargin * 2 + root.popupBackgroundMargin
        implicitHeight: popupBackground.implicitHeight + Appearance.sizes.elevationMargin * 2 + root.popupBackgroundMargin

        mask: Region {
            item: root.interactive ? hitArea : popupBackground
        }

        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        margins {
            left: {
                if (!Config.options.bar.vertical) return root.QsWindow?.mapFromItem(
                    root.hoverTarget,
                    (root.hoverTarget.width - popupBackground.implicitWidth) / 2, 0
                ).x;
                return Appearance.sizes.verticalBarWidth
            }
            top: {
                if (!Config.options.bar.vertical) return Appearance.sizes.barHeight;
                return root.QsWindow?.mapFromItem(
                    root.hoverTarget,
                    (root.hoverTarget.height - popupBackground.implicitHeight) / 2, 0
                ).y;
            }
            right: Appearance.sizes.verticalBarWidth
            bottom: Appearance.sizes.barHeight
        }
        WlrLayershell.namespace: "quickshell:popup"
        WlrLayershell.layer: WlrLayer.Overlay

        Timer {
            id: graceTimer
            interval: root.closeGrace
            onTriggered: if (!root.wanted) root.held = false
        }

        Connections {
            target: root
            function onWantedChanged() {
                if (root.wanted) graceTimer.stop();
                else graceTimer.restart();
            }
        }

        Item {
            id: hitArea
            anchors.fill: parent

            HoverHandler {
                id: contentHover
            }

            // A sibling of popupBackground: the shadow anchors.fill's its target,
            // which QML only allows against a parent or sibling.
            StyledRectangularShadow {
                target: popupBackground
            }

            Rectangle {
                id: popupBackground
                readonly property real margin: 10
                anchors {
                    fill: parent
                    leftMargin: Appearance.sizes.elevationMargin + root.popupBackgroundMargin * (!popupWindow.anchors.left)
                    rightMargin: Appearance.sizes.elevationMargin + root.popupBackgroundMargin * (!popupWindow.anchors.right)
                    topMargin: Appearance.sizes.elevationMargin + root.popupBackgroundMargin * (!popupWindow.anchors.top)
                    bottomMargin: Appearance.sizes.elevationMargin + root.popupBackgroundMargin * (!popupWindow.anchors.bottom)
                }
                implicitWidth: root.contentItem.implicitWidth + margin * 2
                implicitHeight: root.contentItem.implicitHeight + margin * 2
                color: Appearance.m3colors.m3surfaceContainer
                radius: Appearance.rounding.small
                children: [root.contentItem]

                border.width: 1
                border.color: Appearance.colors.colLayer0Border
            }
        }
    }
}
