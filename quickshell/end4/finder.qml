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
import qs.modules.finder

// The app is a list of windows rather than one window: Cmd+N, and launching
// Files again while it is running, each get their own. One process still owns
// all of them -- a cold start spends about a second and a half in Qt engine and
// scene graph setup before anything is drawn, and none of that is recoverable,
// so the second window has to come from the process that is already warm.
Scope {
    id: root

    property var windows: []

    // A freshly launched process becomes the active application as a normal
    // side effect of just being born -- nothing the user did caused it. That
    // transition used to be indistinguishable from the one the Connections
    // below actually cares about (a warm, idle process getting re-activated),
    // so it raced whatever a cold start was ALREADY in the middle of showing
    // on purpose: a "Choose file" click starts the process hidden and polls
    // pickWallpaper() until the window exists, and the birth-activation fired
    // first, found nothing visible yet, and showed a plain window nobody
    // asked for right alongside the picker that arrived a moment later. A
    // real re-activation (the Dock icon, days later) always lands well after
    // this window closes; the one that fires within it is always self-inflicted.
    property bool ignoreEarlyActivation: true

    Timer {
        interval: 3000
        running: true
        onTriggered: root.ignoreEarlyActivation = false
    }

    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme();
        // Started hidden by the login agent so the first real open is warm.
        root.newWindow("", Quickshell.env("QS_FINDER_START_HIDDEN") !== "1");
    }

    Component {
        id: windowComponent

        FinderWindow {
            id: win

            onCloseRequested: root.closeWindow(win)
            onNewWindowRequested: root.newWindow("")
            onPicked: (path, mode) => {
                Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", mode, "--image", path]);
                root.closeWindow(win);
            }
        }
    }

    function newWindow(path: string, show = true, pickMode = ""): var {
        const win = windowComponent.createObject(root, {
            cascade: root.windows.length,
            pickMode: pickMode
        });
        root.windows = [...root.windows, win];
        if (path.length > 0)
            win.navigate(path);
        if (show)
            // One more turn of the event loop before the window is actually
            // shown: pickMode is set via an alias forwarding to a child item
            // (content.pickMode), and the title binding that yabai reads at
            // window creation depends on it. Showing the window in the very
            // same tick as creating it occasionally raced that forwarding, so
            // a fresh picker window was sometimes still titled "Files" at the
            // instant yabai looked, and a rule meant only for a plain window
            // (see src/tools/qs-finder) caught it instead of the picker's own.
            Qt.callLater(() => win.present());
        return win;
    }

    // The last window hides rather than closing, so the process stays warm for
    // the next open. Tearing the engine down would also segfault in Qt's Cocoa
    // window teardown, which is why settings leaves crash reports.
    function closeWindow(win): void {
        if (root.windows.length <= 1) {
            win.visible = false;
            return;
        }
        root.windows = root.windows.filter(w => w !== win);
        win.destroy();
    }

    function present(): void {
        const shown = root.windows.filter(w => w.visible);
        if (shown.length > 0) {
            shown[shown.length - 1].present();
            return;
        }
        if (root.windows.length > 0)
            root.windows[0].present();
        else
            root.newWindow("");
    }

    // Opening an app that is already running does not re-run its launcher -- macOS
    // just activates it -- so the show cannot rely on the script calling present().
    // Activation is the signal: coming to the front with no window means show one.
    Connections {
        target: Qt.application

        function onStateChanged(): void {
            if (!root.ignoreEarlyActivation && Qt.application.state === Qt.ApplicationActive && root.windows.every(w => !w.visible))
                root.present();
        }
    }

    IpcHandler {
        target: "finder"

        // Deliberately not named show(): the CLI owns an `ipc show` verb and a
        // handler function by that name is silently swallowed.
        function present(): void {
            root.present();
        }

        function open(path: string): void {
            const shown = root.windows.filter(w => w.visible);
            if (shown.length === 0) {
                root.present();
            }
            const target = root.windows.filter(w => w.visible).pop();
            if (target) {
                target.navigate(path);
                target.present();
            }
        }

        // A second launch asks for this rather than raising what is already open.
        // A window already hidden is spent first: that is the one the login
        // agent primed, and it is warmer than building another.
        function newWindow(): void {
            const hidden = root.windows.find(w => !w.visible);
            if (hidden)
                hidden.present();
            else
                root.newWindow("");
        }

        // The shell's "Choose file" wallpaper button. macOS's own open panel is
        // a Finder window in all but name, so it comes here instead; picking an
        // image calls switchwall back the same way the wallpaper grid does.
        //
        // A picker gets a window of its own, born knowing it is a picker: it
        // cannot hijack one you are browsing in, and yabai reads a window's
        // title when the window is created, so a window that becomes a picker
        // afterwards is one yabai has already decided to tile.
        //
        // Idempotent on purpose: qs-finder retries this call every 250ms until
        // one lands (a cold start has nothing to wait on otherwise), and if the
        // first try actually landed but reported failure on the way out, the
        // retry arrived anyway -- two calls, one picker. Re-showing whichever
        // picker is already open absorbs that instead of opening a second one.
        function pickWallpaper(mode: string): void {
            const pickerMode = mode === "light" ? "light" : "dark";
            const existing = root.windows.find(w => w.pickMode.length > 0);
            if (existing) {
                existing.pickMode = pickerMode;
                existing.present();
                return;
            }
            root.newWindow("", true, pickerMode);
        }

        // Bind this to a key if you want one press to show and the next to hide.
        function toggle(): void {
            const shown = root.windows.filter(w => w.visible);
            if (shown.length > 0)
                shown.forEach(w => w.visible = false);
            else
                root.present();
        }
    }
}
