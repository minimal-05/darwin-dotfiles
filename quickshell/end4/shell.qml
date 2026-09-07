//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000

// Remove two slashes below and adjust the value to change the UI scale
//@ pragma Env QT_SCALE_FACTOR=0.95

import "modules/common"
import "services"
import "panelFamilies"

import QtQuick
import Quickshell

ShellRoot {
    id: root

    ReloadPopup {}

    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme()
        Hyprsunset.load()
        Cliphist.refresh()
        Wallpapers.load()
        Updates.load()
        YabaiBarSpace.load()
        AirPlay.load()
    }

    LazyLoader {
        active: Config.ready
        component: IllogicalImpulseFamily {}
    }
}

