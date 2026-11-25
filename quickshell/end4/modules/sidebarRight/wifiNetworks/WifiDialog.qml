import qs
import qs.services
import qs.services.network
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

WindowDialog {
    id: root
    backgroundHeight: 600

    WindowDialogTitle {
        text: Translation.tr("Connect to Wi-Fi")
    }
    WindowDialogSeparator {
        visible: !Network.wifiScanning
    }
    StyledIndeterminateProgressBar {
        visible: Network.wifiScanning
        Layout.fillWidth: true
        Layout.topMargin: -8
        Layout.bottomMargin: -8
        Layout.leftMargin: -Appearance.rounding.large
        Layout.rightMargin: -Appearance.rounding.large
    }
    ListView {
        Layout.fillHeight: true
        Layout.fillWidth: true
        Layout.topMargin: -15
        Layout.bottomMargin: -16
        Layout.leftMargin: -Appearance.rounding.large
        Layout.rightMargin: -Appearance.rounding.large

        clip: true
        spacing: 0

        model: ScriptModel {
            values: Network.friendlyWifiNetworks
        }
        delegate: WifiNetworkItem {
            required property WifiAccessPoint modelData
            wifiNetwork: modelData
            width: ListView.view.width
        }
    }
    RowLayout {
        // Un-redacting SSIDs in-process needs com.apple.developer.networking.wifi-info,
        // which needs a paid Apple Developer Program account + provisioning
        // profile this build doesn't have (see src/tools/qs-bundle in
        // quickshell-macos) -- confirmed a hard AMFI launch failure without
        // one, so this dialog can never show real names for other networks.
        // System Settings' Wi-Fi pane is a first-party process, exempt from
        // that restriction, and shows real names today (verified: it lists
        // both the connected network and others by name). So this hands off
        // to it instead of pretending our own list could ever catch up.
        Layout.fillWidth: true
        Layout.topMargin: 4
        Layout.bottomMargin: 4
        visible: Network.friendlyWifiNetworks.some(n => n.nameHidden)
        spacing: 8

        MaterialSymbol {
            text: "location_off"
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnSurfaceVariant
        }
        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: Appearance.colors.colOnSurfaceVariant
            text: Translation.tr("This build can't show real network names. See and join them in System Settings instead.")
        }
        DialogButton {
            buttonText: Translation.tr("Open Wi-Fi Settings")
            onClicked: {
                Quickshell.execDetached(["open", "x-apple.systempreferences:com.apple.wifi-settings-extension"]);
                GlobalStates.sidebarRightOpen = false;
            }
        }
    }
    WindowDialogSeparator {}
    WindowDialogButtonRow {
        DialogButton {
            buttonText: Translation.tr("Details")
            onClicked: {
                Quickshell.execDetached(["bash", "-c", `${Network.ethernet ? Config.options.apps.networkEthernet : Config.options.apps.network}`]);
                GlobalStates.sidebarRightOpen = false;
            }
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