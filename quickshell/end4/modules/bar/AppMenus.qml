pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

/**
 * The frontmost app's menus, behind one button in the bar.
 *
 * SketchyBar slid ten real items into the bar to show these, which shoved
 * everything either side of them open and shut. Hovering a single button and
 * dropping the menus over the desktop leaves the bar's own layout alone.
 *
 * The dropdown is one window, built once and shown and hidden thereafter. The
 * first cut used StyledPopup, which is a LazyLoader: it tore the whole native
 * window down and built a new one on every hover, and re-centred itself on the
 * button as the content resized, so the menu slid out from under the pointer.
 */
MouseArea {
    id: root

    // Both columns are always allocated, so the card is one fixed width for as
    // long as it is open. Letting it widen when the entries arrived pushed it
    // past the right edge of the screen, and the popup positioner slid it ~57px
    // left to fit — straight out from under the pointer, which closed it.
    readonly property int titlesWidth: 170
    readonly property int entriesWidth: 300

    // Both panes are this tall for as long as the dropdown is open. The titles
    // land once, before the pointer has left the button, and nothing after that
    // changes the window's size.
    readonly property real paneHeight: Math.max(titlesColumn.implicitHeight, 300)

    implicitWidth: 26
    implicitHeight: Appearance.sizes.barHeight
    hoverEnabled: true

    // Where the dropdown's window sits, in bar-window coordinates. Recomputed
    // only as it opens: the clock and stats either side change width as they
    // tick, so the button is rarely where it was last time.
    property real popupX: 0

    function reveal(): void {
        const barWindow = root.QsWindow?.window;
        const left = root.QsWindow?.mapFromItem(root, 0, 0).x ?? 0;
        // Clamp here rather than letting the compositor slide it later: sliding
        // happens after the content resizes, which drags the menu out from
        // under the pointer and closes it.
        root.popupX = barWindow ? Math.max(0, Math.min(left, barWindow.width - dropdown.implicitWidth)) : left;
        dropdown.visible = true;
    }

    function dismiss(): void {
        closeTimer.stop();
        hoverProxy.wantOpen = false;
        dropdown.visible = false;
        dropdownContent.selected = -1;
        MacMenus.close();
    }

    MaterialSymbol {
        anchors.centerIn: parent
        text: "menu"
        iconSize: Appearance.font.pixelSize.large
        fill: dropdown.visible ? 1 : 0
        color: dropdown.visible ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

    QtObject {
        id: hoverProxy

        // Hovering the button or the dropdown counts as hovering the whole
        // control, so sliding from one into the other never closes it.
        readonly property bool wanted: root.containsMouse || cardHover.hovered
        property bool wantOpen: false
    }

    Connections {
        target: hoverProxy

        function onWantedChanged() {
            if (hoverProxy.wanted) {
                closeTimer.stop();
                hoverProxy.wantOpen = true;
                // Read the menus before the dropdown is up, so what is listed is
                // the app that was frontmost when the pointer arrived.
                MacMenus.refresh();
                root.reveal();
            } else {
                closeTimer.restart();
            }
        }
    }

    Timer {
        id: closeTimer

        // Crossing the seam between the bar and the dropdown drops both hovers
        // for a frame. Closing on that would put the menu out of reach.
        interval: 220
        onTriggered: if (!hoverProxy.wanted) root.dismiss()
    }

    Timer {
        id: pick

        // Short enough not to read as lag, long enough that sweeping the list
        // does not fire the helper once per row crossed. Menus already read
        // once this open come back from the cache and skip this entirely.
        interval: 45
        onTriggered: if (dropdownContent.selected >= 0) MacMenus.open(dropdownContent.selected)
    }

    // A PanelWindow, not a PopupWindow: the Cocoa backend only installs pointer
    // tracking on panels, so hover inside a popup window arrives erratically or
    // not at all — the dropdown would close the moment you reached for it.
    PanelWindow {
        id: dropdown

        readonly property real pad: Appearance.sizes.elevationMargin

        color: "transparent"
        visible: false
        anchors.top: true
        anchors.left: true
        implicitWidth: card.implicitWidth + dropdown.pad * 2
        implicitHeight: card.implicitHeight + dropdown.pad * 2
        margins.top: Appearance.sizes.barHeight
        margins.left: root.popupX

        // Only the card takes input; the elevation margin around it stays
        // click-through so the desktop underneath is still reachable.
        mask: Region {
            item: card
        }

        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        WlrLayershell.namespace: "quickshell:popup"
        WlrLayershell.layer: WlrLayer.Overlay

        StyledRectangularShadow {
            target: card
        }

        Rectangle {
            id: card

            anchors.centerIn: parent
            implicitWidth: layout.implicitWidth + 8
            implicitHeight: layout.implicitHeight + 8
            radius: Appearance.rounding.small
            color: Appearance.m3colors.m3surfaceContainer
            border.width: 1
            border.color: Appearance.colors.colLayer0Border

            HoverHandler {
                id: cardHover
            }

            Item {
                id: dropdownContent

                // Which top-level menu the pointer is resting on.
                property int selected: -1

                anchors.fill: parent
                anchors.margins: 4

                RowLayout {
                    id: layout

                    anchors.fill: parent
                    spacing: 4

                    ColumnLayout {
                        id: titlesColumn

                        Layout.alignment: Qt.AlignTop
                        Layout.preferredWidth: root.titlesWidth
                        spacing: 2

                        Repeater {
                            model: MacMenus.blocked ? [] : MacMenus.titles

                            AppMenuRow {
                                required property var modelData

                                Layout.fillWidth: true
                                label: modelData.title
                                showChevron: dropdownContent.selected === modelData.id
                                selected: dropdownContent.selected === modelData.id
                                onEntered: {
                                    dropdownContent.selected = modelData.id;
                                    pick.restart();
                                }
                                releaseAction: () => {
                                    dropdownContent.selected = modelData.id;
                                    pick.stop();
                                    MacMenus.open(modelData.id);
                                }
                            }
                        }

                        AppMenuRow {
                            Layout.fillWidth: true
                            visible: MacMenus.blocked
                            label: Translation.tr("Grant Accessibility to menus")
                            labelColor: Appearance.m3colors.m3error
                            releaseAction: () => {
                                MacMenus.grantAccessibility();
                                root.dismiss();
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillHeight: true
                        Layout.topMargin: 2
                        Layout.bottomMargin: 2
                        implicitWidth: 1
                        color: Appearance.m3colors.m3outlineVariant
                    }

                    // Sized off the menu titles, never off its own contents.
                    // Letting the entries decide the height resized the window
                    // mid-hover, and a resize drops the pointer: hover only
                    // comes back on the next mouse move, so pausing to read a
                    // menu closed it. History and Bookmarks would also run
                    // longer than the screen is tall.
                    Item {
                        Layout.alignment: Qt.AlignTop
                        Layout.preferredWidth: root.entriesWidth
                        Layout.preferredHeight: root.paneHeight

                        StyledText {
                            anchors.centerIn: parent
                            visible: MacMenus.entries.length === 0
                            text: Translation.tr("Pick a menu")
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.smallie
                        }

                    StyledListView {
                        id: entriesPane

                        anchors.fill: parent
                        clip: true
                        spacing: 2
                        model: MacMenus.entries

                        // The per-item entrance animations are meant for a list
                        // that changes now and then, not one replaced wholesale
                        // every time the pointer crosses a menu title.
                        animateAppearance: false
                        popin: false

                        delegate: AppMenuRow {
                            required property var modelData

                            width: entriesPane.width
                            label: modelData.title
                            trailing: modelData.shortcut
                            releaseAction: () => {
                                MacMenus.press(dropdownContent.selected, modelData.id);
                                root.dismiss();
                            }
                        }
                    }
                    }
                }
            }
        }
    }
}
