import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

WindowDialog {
    id: root

    backgroundHeight: 520

    WindowDialogTitle {
        text: Translation.tr("Screen Mirroring")
    }

    WindowDialogParagraph {
        Layout.fillWidth: true
        text: Translation.tr("Receivers on this network. macOS keeps the last step to itself — picking one opens Apple's picker to start mirroring.")
    }

    WindowDialogSeparator {
        visible: !AirPlay.scanning
    }

    StyledIndeterminateProgressBar {
        visible: AirPlay.scanning
        Layout.fillWidth: true
        Layout.topMargin: -8
        Layout.bottomMargin: -8
        Layout.leftMargin: -Appearance.rounding.large
        Layout.rightMargin: -Appearance.rounding.large
    }

    Item {
        Layout.fillHeight: true
        Layout.fillWidth: true
        Layout.topMargin: -15
        Layout.bottomMargin: -16
        Layout.leftMargin: -Appearance.rounding.large
        Layout.rightMargin: -Appearance.rounding.large

        StyledListView {
            anchors.fill: parent
            clip: true
            spacing: 0
            model: AirPlay.devices

            delegate: AirPlayDeviceItem {
                required property var modelData

                deviceName: modelData
                width: ListView.view.width
                onHandOff: {
                    MacMenus.controlCentre();
                    GlobalStates.sidebarRightOpen = false;
                    root.dismiss();
                }
            }
        }

        PagePlaceholder {
            shown: AirPlay.devices.length === 0 && !AirPlay.scanning
            icon: "cast"
            title: Translation.tr("No receivers")
            description: Translation.tr("Nothing is advertising AirPlay on this network.")
        }
    }

    WindowDialogSeparator {}

    WindowDialogButtonRow {
        DialogButton {
            buttonText: Translation.tr("Rescan")
            onClicked: AirPlay.start()
        }

        Item {
            Layout.fillWidth: true
        }

        DialogButton {
            buttonText: Translation.tr("Done")
            onClicked: root.dismiss()
        }
    }
}
