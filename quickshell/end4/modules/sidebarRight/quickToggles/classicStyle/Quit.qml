import qs.modules.common.widgets
import qs.services
import Quickshell
import QtQuick

QuickToggleButton {
    id: root
    toggled: false
    buttonIcon: "power_settings_new"
    onClicked: {
        Quickshell.execDetached(["qs-quit"])
    }
    StyledToolTip {
        text: Translation.tr("Quit Quickshell")
    }
}
