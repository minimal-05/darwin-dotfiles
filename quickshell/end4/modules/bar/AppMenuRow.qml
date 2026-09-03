pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

// One row of the app-menu popup: a RippleButton like the tray menu's entries,
// set in the same face and colour as the value rows of the other bar popups so
// the whole popup reads as one of them.
RippleButton {
    id: root

    property string label: ""
    property string trailing: ""
    property bool showChevron: false
    property bool selected: false
    property color labelColor: Appearance.colors.colOnSurfaceVariant

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
            color: root.labelColor
            elide: Text.ElideRight
            textFormat: Text.PlainText
        }

        StyledText {
            visible: root.trailing.length > 0
            text: root.trailing
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
