//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000

// Remove two slashes below and adjust the value to change the UI scale
//@ pragma Env QT_SCALE_FACTOR=0.95

import qs
import "modules/common"
import "services"
import "panelFamilies"

import QtQuick
import Quickshell
import Quickshell.Io

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
        FusionMode.load()
    }

    LazyLoader {
        active: Config.ready && !GlobalStates.shellHidden
        component: IllogicalImpulseFamily {}
    }

    // Hide the whole shell without quitting it. `qs-quit` boots the launchd job
    // out, so coming back is a full Qt start; this only drops the panel
    // family, which reloads from already-parsed QML. No `show()`: the CLI eats
    // that name as its own `ipc show` verb.
    IpcHandler {
        target: "shell"

        function toggle(): void {
            GlobalStates.shellHidden = !GlobalStates.shellHidden
        }

        function hide(): void {
            GlobalStates.shellHidden = true
        }

        function reveal(): void {
            GlobalStates.shellHidden = false
        }
    }
}

