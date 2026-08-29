import qs.modules.common.models.quickToggles
import qs.modules.common.widgets
import QtQuick

AndroidQuickToggleButton {
    id: button

    toggleModel: ScreenMirroringToggle {}

    // There is no on/off state to flip, so a press at any cell size opens the
    // receiver list rather than only doing so on the wide one.
    mainAction: () => button.openMenu()
}
