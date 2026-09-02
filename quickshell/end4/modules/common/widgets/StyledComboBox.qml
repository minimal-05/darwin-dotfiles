pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
* A Material 3 dropdown. The option list expands inline, directly beneath
* the trigger, growing the surrounding layout -- the same "push the rest of
* the content down" pattern macOS's own Control Center audio-device picker
* uses -- instead of floating a separate window over everything.
*
* A floating popup, even a proper Quickshell PanelWindow built the way
* DockMenu/SysTrayMenu build theirs, is still a second window whose stacking
* relative to a screen-region selection isn't this app's to control, and it
* showed up over one anyway. Inline content can't: it's just part of this
* window, exactly as visible to a screenshot as any other row already on
* the page, so nothing extra has to know a screenshot is being taken.
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

    spacing: 0
    Layout.fillWidth: true

    // A snip overlay covers the screen but cannot take the pointer, so a
    // click meant for the region selection could otherwise fall through and
    // open this: refuse to, and collapse it if one starts while it's open.
    Connections {
        target: GlobalStates
        function onRegionSelectorOpenChanged() {
            if (GlobalStates.regionSelectorOpen)
                root.popupOpen = false;
        }
    }

    RippleButton {
        id: trigger
        Layout.fillWidth: true
        implicitHeight: 40
        rippleEnabled: false
        releaseAction: () => {
            if (!GlobalStates.regionSelectorOpen)
                root.popupOpen = !root.popupOpen;
        }

        background: Rectangle {
            topLeftRadius: trigger.height / 2
            topRightRadius: trigger.height / 2
            bottomLeftRadius: root.popupOpen ? Appearance.rounding.unsharpen : trigger.height / 2
            bottomRightRadius: root.popupOpen ? Appearance.rounding.unsharpen : trigger.height / 2
            color: (trigger.down && !root.popupOpen) ? Appearance.colors.colSecondaryContainerActive : trigger.hovered
                                                       ? Appearance.colors.colSecondaryContainerHover :
                                                         Appearance.colors.colSecondaryContainer

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
            Behavior on bottomLeftRadius {
                NumberAnimation { duration: 80; easing.type: Easing.OutQuad }
            }
            Behavior on bottomRightRadius {
                NumberAnimation { duration: 80; easing.type: Easing.OutQuad }
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
                    NumberAnimation { duration: 80; easing.type: Easing.OutQuad }
                }
            }
        }
    }

    Rectangle {
        id: listPanel
        Layout.fillWidth: true
        clip: true

        topLeftRadius: Appearance.rounding.unsharpen
        topRightRadius: Appearance.rounding.unsharpen
        bottomLeftRadius: Appearance.rounding.normal
        bottomRightRadius: Appearance.rounding.normal
        color: Appearance.m3colors.m3surfaceContainerHigh

        implicitHeight: root.popupOpen ? Math.min(listView.contentHeight + 16, 300) : 0
        opacity: root.popupOpen ? 1 : 0

        // elementMoveFast (200ms, used everywhere else in this file) still read
        // as sluggish for an expand/collapse the user checks repeatedly -- cut
        // to a flat 80ms rather than reusing a shared token.
        Behavior on implicitHeight {
            NumberAnimation { duration: 80; easing.type: Easing.OutQuad }
        }
        Behavior on opacity {
            NumberAnimation { duration: 80; easing.type: Easing.OutQuad }
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
                                                     ColorUtils.transparentize(Appearance.colors.colLayer3, 1)
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
