pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
* A Material 3 dropdown, built the same way AppMenus.qml builds the bar's
* app-menu dropdown: one PanelWindow, created once and shown and hidden
* thereafter (not torn down and rebuilt per toggle -- see AppMenus.qml's own
* note on why StyledPopup, a LazyLoader, doesn't work for content you need
* to click into), with no animation on open/close, matching it and every
* other end4 menu (DockMenu, SysTrayMenu) exactly.
*
* Closes on GlobalStates.regionSelectorOpen, the same guard StyledPopup uses
* to keep the bar's hover popups out of a screen-region selection. That flag
* is a per-process singleton, though, and this component is also used
* inside Settings, which runs as its own separate `quickshell -p
* settings.qml` process with a disconnected copy that never sees it change.
* Window.active is a plain QtQuick attached property scoped to this window
* specifically, so it closes on that too regardless of which process it is
* running in.
*
* ponytail: mouse-only, like DockMenu and SysTrayMenu -- no arrow-key/typeahead
* navigation. Add it if a dropdown with many options actually needs it.
*/
ColumnLayout {
    id: root

    property var model: []
    property string textRole: ""
    property string buttonIcon: ""
    property int currentIndex: -1
    property bool popupOpen: false

    signal activated(int index)

    function textFor(item): string {
        return (root.textRole.length > 0 && typeof item === 'object') ? (item?.[root.textRole] ?? "") : String(
                                                                            item ?? "");
    }
    function iconFor(item): string {
        return (typeof item === 'object' && item?.icon) ? item.icon : "";
    }

    readonly property var currentModelItem: (root.currentIndex >= 0 && root.currentIndex < root.model.length)
                                            ? root.model[root.currentIndex] : undefined
    readonly property string displayText: root.textFor(root.currentModelItem)

    readonly property point anchorPoint: {
        const qsWindow = root.QsWindow;
        if (qsWindow?.window)
        return qsWindow.mapFromItem(root, 0, root.height);
        return root.mapToGlobal(0, root.height);
    }

    spacing: 0
    Layout.fillWidth: true

    Connections {
        target: GlobalStates
        function onRegionSelectorOpenChanged() {
            if (GlobalStates.regionSelectorOpen)
                root.popupOpen = false;
        }
    }
    Window.onActiveChanged: if (!Window.active)
    root.popupOpen = false

    RippleButton {
        id: trigger
        Layout.fillWidth: true
        implicitHeight: 40
        buttonRadius: height / 2
        rippleEnabled: false
        colBackground: Appearance.colors.colSecondaryContainer
        colBackgroundHover: Appearance.colors.colSecondaryContainerHover

        releaseAction: () => {
            if (!GlobalStates.regionSelectorOpen && Window.active)
                root.popupOpen = !root.popupOpen;
        }

        contentItem: RowLayout {
            anchors.fill: parent
            spacing: 8
            anchors.leftMargin: 16
            anchors.rightMargin: 16

            Loader {
                Layout.alignment: Qt.AlignVCenter
                active: root.iconFor(root.currentModelItem).length > 0 || root.buttonIcon.length > 0
                visible: active
                sourceComponent: MaterialSymbol {
                    text: root.iconFor(root.currentModelItem) || root.buttonIcon
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                color: Appearance.colors.colOnSecondaryContainer
                text: root.displayText
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }

            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                text: "keyboard_arrow_down"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnSecondaryContainer
                rotation: root.popupOpen ? 180 : 0
            }
        }
    }

    PanelWindow {
        id: popupWindow
        visible: root.popupOpen && !GlobalStates.regionSelectorOpen
        color: "transparent"

        readonly property real pad: Appearance.sizes.elevationMargin

        anchors {
            top: true
            left: true
        }
        implicitWidth: card.implicitWidth + popupWindow.pad * 2
        implicitHeight: card.implicitHeight + popupWindow.pad * 2
        margins.top: root.anchorPoint.y
        margins.left: root.anchorPoint.x

        // Only the card takes input; the elevation margin around it stays
        // click-through, matching AppMenus.qml's dropdown.
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
            implicitWidth: root.width
            implicitHeight: Math.min(listView.contentHeight + 16, 300)
            radius: Appearance.rounding.small
            color: Appearance.m3colors.m3surfaceContainer
            border.width: 1
            border.color: Appearance.colors.colLayer0Border

            StyledListView {
                id: listView
                anchors.fill: parent
                anchors.margins: 8
                clip: true
                spacing: 2
                animateAppearance: false

                model: root.model
                delegate: RippleButton {
                    id: rowButton
                    required property var modelData
                    required property int index

                    width: ListView.view ? ListView.view.width : root.width
                    implicitHeight: 40
                    buttonRadius: Appearance.rounding.small

                    readonly property bool isCurrent: root.currentIndex === rowButton.index
                    colBackground: rowButton.isCurrent ? Appearance.colors.colSecondaryContainer :
                                                         ColorUtils.transparentize(Appearance.colors.colLayer3,
                                                                                   1)
                    colBackgroundHover: rowButton.isCurrent ? Appearance.colors.colSecondaryContainerHover :
                                                              Appearance.colors.colLayer3Hover
                    colRipple: rowButton.isCurrent ? Appearance.colors.colSecondaryContainerActive :
                                                     Appearance.colors.colLayer3Active

                    releaseAction: () => {
                        root.currentIndex = rowButton.index;
                        root.activated(rowButton.index);
                        root.popupOpen = false;
                    }

                    contentItem: RowLayout {
                        anchors.fill: parent
                        spacing: 8
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12

                        Loader {
                            Layout.alignment: Qt.AlignVCenter
                            active: root.iconFor(rowButton.modelData).length > 0
                            visible: active
                            sourceComponent: MaterialSymbol {
                                text: root.iconFor(rowButton.modelData)
                                iconSize: Appearance.font.pixelSize.larger
                                color: rowButton.isCurrent ? Appearance.colors.colOnSecondaryContainer :
                                                             Appearance.colors.colOnLayer3
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            color: rowButton.isCurrent ? Appearance.colors.colOnSecondaryContainer :
                                                         Appearance.colors.colOnLayer3
                            text: root.textFor(rowButton.modelData)
                            elide: Text.ElideRight
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }
        }
    }
}
