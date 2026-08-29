//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000

// Adjust this to make the app smaller or larger
//@ pragma Env QT_SCALE_FACTOR=0.95

import QtQuick
import QtQuick.Window
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.ii.finder

// The file manager as a standalone application, the same way end-4 ships its
// settings window. This matters beyond tidiness: a quickshell process that owns
// no PanelWindow deliberately stays a *regular* macOS app -- Dock icon, menu
// bar, cmd-tab and Spotlight -- while the shell process is an accessory that
// never activates. Running the Finder here rather than as a panel in the shell
// is what makes it launchable from Spotlight at all.
// Window, not ApplicationWindow: ApplicationWindow insets its content by the
// titlebar height (28pt) as a safe area, and this fork already strips the
// titlebar for panel-less processes -- so that inset was 28pt of dead space at
// the top of every window with nothing above it.
Window {
    id: root

    visible: true
    onClosing: Qt.quit()
    title: "Files"

    minimumWidth: 360
    minimumHeight: 280
    width: 1000
    height: 640
    color: Appearance.m3colors.m3background

    Component.onCompleted: MaterialThemeLoader.reapplyTheme()

    FinderContent {
        anchors.fill: parent
    }
}
