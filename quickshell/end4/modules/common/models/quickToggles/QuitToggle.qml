import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    name: Translation.tr("Quit Quickshell")
    hasStatusText: false
    toggled: false
    icon: "power_settings_new"

    mainAction: () => {
        Quickshell.execDetached(["qs-quit"])
    }

    tooltipText: Translation.tr("Quit Quickshell")
}
