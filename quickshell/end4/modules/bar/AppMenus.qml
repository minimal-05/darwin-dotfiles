import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick

/**
 * The frontmost app's menus, behind one button in the bar. Hover to drop them,
 * the same way the clock and resource widgets either side of it drop theirs:
 * the popup itself is AppMenusPopup, a StyledPopup.
 *
 * SketchyBar slid ten real items into the bar to show these, which shoved
 * everything either side of them open and shut. One button and a popup leave
 * the bar's own layout alone.
 */
MouseArea {
    id: root

    implicitWidth: 26
    implicitHeight: Appearance.sizes.barHeight
    hoverEnabled: !Config.options.bar.tooltips.clickToShow

    MaterialSymbol {
        anchors.centerIn: parent
        text: "menu"
        iconSize: Appearance.font.pixelSize.large
        fill: menus.active ? 1 : 0
        color: menus.active ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

    AppMenusPopup {
        id: menus
        hoverTarget: root
    }
}
