//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000

// Adjust this to make the app smaller or larger
//@ pragma Env QT_SCALE_FACTOR=0.95

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.preview

// Window, not ApplicationWindow: ApplicationWindow insets its content by the
// titlebar height as a safe area, and this fork already strips the titlebar for
// panel-less processes -- so that inset is dead space with nothing above it.
//
// One window that swaps images, not one per file: opening a second screenshot
// while looking at the first is what the arrow keys are for.
Window {
    id: root

    // The launcher hands the first file over in the environment; every later
    // open arrives by IPC, because by then this process is already up.
    readonly property string startupPath: Quickshell.env("QS_PREVIEW_PATH") ?? ""

    // Started hidden by the launcher when it is only priming the process.
    visible: Quickshell.env("QS_PREVIEW_START_HIDDEN") !== "1"
    title: content.fileName.length > 0 ? content.fileName : "Preview"

    minimumWidth: 420
    minimumHeight: 320
    width: 1100
    height: 760
    color: Appearance.m3colors.m3background

    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme();
        if (root.startupPath.length > 0)
            content.open(root.startupPath);
    }

    // Closing hides rather than quits, the same bargain the file manager makes:
    // a cold start is ~1.5s of Qt engine and scene graph setup that cannot be
    // recovered, and tearing the engine down segfaults in Qt's Cocoa teardown.
    onClosing: close => {
        close.accepted = false;
        root.visible = false;
    }

    function present(): void {
        root.visible = true;
        root.raise();
        root.requestActivate();
    }

    // Opening an app that is already running does not re-run its launcher --
    // macOS just activates it -- so coming to the front with no window is the
    // signal to show one.
    Connections {
        target: Qt.application

        function onStateChanged(): void {
            if (Qt.application.state === Qt.ApplicationActive && !root.visible && content.path.length > 0)
                root.present();
        }
    }

    IpcHandler {
        target: "preview"

        // Deliberately not named show(): the CLI owns an `ipc show` verb and a
        // handler function by that name is silently swallowed.
        function open(path: string): void {
            content.open(path);
            root.present();
        }

        function present(): void {
            root.present();
        }

        function toggle(): void {
            if (root.visible)
                root.visible = false;
            else
                root.present();
        }
    }

    PreviewContent {
        id: content

        anchors.fill: parent

        onCloseRequested: root.visible = false
    }
}
