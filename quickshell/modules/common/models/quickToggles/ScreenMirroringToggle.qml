import QtQuick
import qs.services
import qs.modules.common

QuickToggleModel {
    name: Translation.tr("Screen Mirroring")
    hasStatusText: false
    toggled: false
    icon: "cast"
    hasMenu: true

    // Nothing to toggle: there is no way to read or set the system's mirroring
    // state without Apple's entitlement, so every press opens the picker. The
    // button wires that up — see AndroidScreenMirroringToggle.
    mainAction: () => {}

    tooltipText: Translation.tr("Screen Mirroring")
}
