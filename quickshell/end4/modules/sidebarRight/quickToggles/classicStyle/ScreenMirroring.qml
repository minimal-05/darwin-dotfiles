import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.services

QuickToggleButton {
    id: root
    // Nothing to toggle: there is no way to read or set the system's
    // mirroring state without Apple's entitlement (see AirPlay.qml), so this
    // just reflects what AirPlay.qml's system_profiler check last found and
    // every press opens the picker, same as the Android build's version.
    toggled: Object.keys(AirPlay.mirroring).length > 0
    buttonIcon: "cast"

    StyledToolTip {
        text: Translation.tr("Screen Mirroring")
    }
}
