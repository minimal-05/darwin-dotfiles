import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

DialogListItem {
    id: root

    required property string deviceName

    signal handOff()

    onClicked: root.handOff()

    contentItem: RowLayout {
        anchors {
            fill: parent
            topMargin: root.verticalPadding
            bottomMargin: root.verticalPadding
            leftMargin: root.horizontalPadding
            rightMargin: root.horizontalPadding
        }
        spacing: 10

        MaterialSymbol {
            text: "cast"
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnSurfaceVariant
        }

        StyledText {
            Layout.fillWidth: true
            text: root.deviceName
            color: Appearance.colors.colOnSurfaceVariant
            elide: Text.ElideRight
            textFormat: Text.PlainText
        }

        MaterialSymbol {
            text: "open_in_new"
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colSubtext
        }
    }
}
