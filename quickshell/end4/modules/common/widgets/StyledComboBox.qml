pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
* A Material 3 dropdown. Built on RippleButton + PanelWindow (the same
* primitives DockMenu/SysTrayMenu use for their own floating menus) rather
* than QtQuick.Controls' ComboBox/Popup: that Popup opens its own plain Qt
* window, which isn't part of the app's own overlay/level handling and so
* isn't covered by the region-selector guard below the way every other
* end4 popup is.
*
* ponytail: mouse-only, like DockMenu and SysTrayMenu -- no arrow-key/typeahead
* navigation. Add it if a dropdown with many options actually needs it.
*/
RippleButton {
    id: root

    property var model: []
    property string textRole: ""
    property string buttonIcon: ""
    property int currentIndex: -1
    property color colBackgroundActive: Appearance.colors.colSecondaryContainerActive
    property bool popupOpen: false

    signal activated(int index)

    // buttonRadius, colBackground and colBackgroundHover already exist on
    // RippleButton -- rebind them rather than redeclaring (qmllint flags a
    // redeclare as shadowing the base property).
    buttonRadius: height / 2
    colBackground: Appearance.colors.colSecondaryContainer
    colBackgroundHover: Appearance.colors.colSecondaryContainerHover

    function textFor(item): string {
        return (root.textRole.length > 0 && typeof item === 'object') ? (item?.[root.textRole] ?? "") : String(item ?? "");
    }
    function iconFor(item): string {
        return (typeof item === 'object' && item?.icon) ? item.icon : "";
    }

    readonly property var currentModelItem: (root.currentIndex >= 0 && root.currentIndex < root.model.length)
                                            ? root.model[root.currentIndex] : undefined
    readonly property string displayText: root.textFor(root.currentModelItem)

    implicitHeight: 40
    Layout.fillWidth: true
    releaseAction: () => root.popupOpen = !root.popupOpen

    // A snip overlay covers the screen but cannot take the pointer, so a
    // click meant for the region selection would otherwise fall through and
    // open this: close it (and keep it closed) whenever one starts.
    Connections {
        target: GlobalStates
        function onRegionSelectorOpenChanged() {
            if (GlobalStates.regionSelectorOpen)
                root.popupOpen = false;
        }
    }

    background: Rectangle {
        topLeftRadius: root.buttonRadius
        topRightRadius: root.buttonRadius
        bottomLeftRadius: root.popupOpen ? Appearance.rounding.unsharpen : root.buttonRadius
        bottomRightRadius: root.popupOpen ? Appearance.rounding.unsharpen : root.buttonRadius
        color: (root.down && !root.popupOpen) ? root.colBackgroundActive : root.hovered
                                                ? root.colBackgroundHover : root.colBackground

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
        Behavior on bottomLeftRadius {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on bottomRightRadius {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
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
            Behavior on rotation {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }
    }

    Loader {
        active: root.popupOpen && !GlobalStates.regionSelectorOpen

        sourceComponent: PanelWindow {
            id: popupWindow
            color: "#03000000" // Drawn, not transparent: see DockMenu's note on scrim hit-testing.

            // Recomputed only as it opens, like AppMenus.qml's dropdown: good
            // enough for where the button was when it was clicked.
            property point anchorPoint: root.mapToGlobal(0, root.height)

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            WlrLayershell.namespace: "quickshell:popup"
            WlrLayershell.layer: WlrLayer.Overlay

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onPressed: root.popupOpen = false
            }

            StyledRectangularShadow {
                target: card
            }

            Rectangle {
                id: card
                readonly property real gap: Appearance.sizes.elevationMargin

                x: Math.max(gap, Math.min(popupWindow.anchorPoint.x, popupWindow.width - width - gap))
                y: Math.min(popupWindow.anchorPoint.y + 2, popupWindow.height - height - gap)
                width: root.width
                height: Math.min(listView.contentHeight + 16, 300)

                topLeftRadius: Appearance.rounding.unsharpen
                topRightRadius: Appearance.rounding.unsharpen
                bottomLeftRadius: Appearance.rounding.normal
                bottomRightRadius: Appearance.rounding.normal
                color: Appearance.m3colors.m3surfaceContainerHigh

                opacity: 0
                Component.onCompleted: opacity = 1
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                // Swallow clicks that land on the card but not on a row, so
                // they do not reach the scrim and close the dropdown.
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                }

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
                                                             ColorUtils.transparentize(
                                                                 Appearance.colors.colLayer3, 1)
                        colBackgroundHover: rowButton.isCurrent
                                            ? Appearance.colors.colSecondaryContainerHover :
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
}
