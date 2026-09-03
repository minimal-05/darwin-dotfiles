pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell.Wayland

/**
 * The frontmost app's menus, as a bar popup: the same StyledPopup the clock
 * and resource popups are, so it sits, looks, opens and closes exactly as they
 * do -- and stays out of a screen-region selection the same way -- with
 * `interactive` on so it can be reached into and clicked.
 */
StyledPopup {
    id: root
    interactive: true

    // Both panes keep one size for as long as the popup is open: StyledPopup
    // re-centres on the button as its content resizes, which would slide the
    // rows out from under the pointer. History and Bookmarks would also run
    // longer than the screen is tall.
    readonly property int titlesWidth: 170
    readonly property int entriesWidth: 300
    readonly property real paneHeight: Math.max(titlesPane.implicitHeight, 300)

    // Which top-level menu the pointer is resting on.
    property int selected: -1

    function dismiss(): void {
        root.held = false;
    }

    onActiveChanged: {
        if (root.active) {
            // Read the menus as the popup comes up, so what is listed is the
            // app that was frontmost when the pointer arrived.
            MacMenus.refresh();
        } else {
            root.selected = -1;
            MacMenus.close();
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: 8

        // Short enough not to read as lag, long enough that sweeping the list
        // does not fire the helper once per row crossed. Menus already read
        // once this open come back from the cache and skip this entirely.
        Timer {
            id: pick
            interval: 45
            onTriggered: if (root.selected >= 0) MacMenus.open(root.selected)
        }

        StyledPopupHeaderRow {
            icon: "menu"
            label: ToplevelManager.activeToplevel?.appId ?? Translation.tr("Menus")
        }

        Row {
            spacing: 12

            Column {
                id: titlesPane
                anchors.top: parent.top
                width: root.titlesWidth
                spacing: 2

                Repeater {
                    model: MacMenus.blocked ? [] : MacMenus.titles

                    AppMenuRow {
                        required property var modelData

                        width: parent.width
                        label: modelData.title
                        showChevron: root.selected === modelData.id
                        selected: root.selected === modelData.id
                        onEntered: {
                            root.selected = modelData.id;
                            pick.restart();
                        }
                        releaseAction: () => {
                            root.selected = modelData.id;
                            pick.stop();
                            MacMenus.open(modelData.id);
                        }
                    }
                }

                AppMenuRow {
                    width: parent.width
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
                anchors.top: parent.top
                width: 1
                height: root.paneHeight
                color: Appearance.m3colors.m3outlineVariant
            }

            Item {
                id: entriesPane
                anchors.top: parent.top
                width: root.entriesWidth
                height: root.paneHeight

                StyledText {
                    anchors.centerIn: parent
                    visible: MacMenus.entries.length === 0
                    text: Translation.tr("Pick a menu")
                    color: Appearance.colors.colSubtext
                }

                StyledListView {
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
                            MacMenus.press(root.selected, modelData.id);
                            root.dismiss();
                        }
                    }
                }
            }
        }
    }
}
