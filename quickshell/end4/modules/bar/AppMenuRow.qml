pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

// One row of the app-menu dropdown, shaped like the tray menu's own entries so
// the two read as the same menu system.
RippleButton {
    id: root

    property string label: ""
    property string trailing: ""
    property bool showChevron: false
    property bool selected: false
    property color labelColor: Appearance.colors.colOnLayer1

    signal entered()

    horizontalPadding: 12
    implicitHeight: 36
    buttonRadius: Appearance.rounding.small
    colBackground: root.selected ? Appearance.colors.colLayer2 : ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1)
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colRipple: Appearance.colors.colLayer1Active

    onHoveredChanged: if (root.hovered) root.entered()

    contentItem: RowLayout {
        anchors {
            verticalCenter: parent.verticalCenter
            left: parent.left
            right: parent.right
            leftMargin: root.horizontalPadding
            rightMargin: root.horizontalPadding
        }
        spacing: 8

        StyledText {
            Layout.fillWidth: true
            text: root.label
            font.pixelSize: Appearance.font.pixelSize.smallie
            color: root.labelColor
            elide: Text.ElideRight
            textFormat: Text.PlainText
        }

        StyledText {
            visible: root.trailing.length > 0
            text: root.trailing
            font.pixelSize: Appearance.font.pixelSize.smallie
            color: Appearance.colors.colSubtext
            textFormat: Text.PlainText
        }

        MaterialSymbol {
            visible: root.showChevron
            text: "chevron_right"
            iconSize: 20
            color: Appearance.colors.colSubtext
        }
    }
}
