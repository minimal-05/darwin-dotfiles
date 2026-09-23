import qs.modules.common
import qs.services
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
pragma Singleton
pragma ComponentBehavior: Bound

Singleton {
    id: root
    property bool barOpen: true
    property bool crosshairOpen: false
    property bool sidebarLeftOpen: false
    property bool sidebarRightOpen: false
    property bool mediaControlsOpen: false
    property bool osdBrightnessOpen: false
    property bool osdVolumeOpen: false
    property bool oskOpen: false
    property bool overlayOpen: false
    property bool overviewOpen: false
    property bool regionSelectorOpen: false
    property bool searchOpen: false
    // Set by `qs-ipc shell toggle` (super u). Unloads every panel family, so
    // the shell goes away visually without the process dying -- a hidden shell
    // comes back in a QML reload instead of a cold Qt start.
    property bool shellHidden: false
    property bool screenLocked: false
    property bool screenLockContainsCharacters: false
    property bool screenUnlockFailed: false
    property bool sessionOpen: false
    // The confirmation in front of study mode. Entering is a one-way door for
    // the duration, so it never starts on a single click.
    property bool studyModeConfirmOpen: false
    property bool studyTrackerOpen: false
    property bool superDown: false
    property bool superReleaseMightTrigger: true
    property bool wallpaperSelectorOpen: false
    property bool workspaceShowNumbers: false
    // Kept for a config that still reads qs-window-thumbs stills. The overview
    // tiles are live ScreencopyView captures (ScreenCaptureKit, in-process) and
    // no longer bump this.
    property int windowThumbRevision: 0
    readonly property string windowThumbDir: (Quickshell.env("XDG_RUNTIME_DIR") ?? "/tmp/quickshell") + "/quickshell/thumbs"

    onSidebarRightOpenChanged: {
        if (GlobalStates.sidebarRightOpen) {
            Notifications.timeoutAll();
            Notifications.markAllRead();
        }
    }

    GlobalShortcut {
        name: "workspaceNumber"
        description: "Hold to show workspace numbers, release to show icons"

        onPressed: {
            root.superDown = true
        }
        onReleased: {
            root.superDown = false
        }
    }
}