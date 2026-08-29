pragma Singleton

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Keeps the Material You palette pointed at the wallpaper macOS is actually
 * showing.
 *
 * On Linux the desktop picture only ever changes through switchwall.sh, so
 * end-4 can regenerate the palette at the moment of the change. On macOS the
 * picture belongs to the window server: System Settings, a bare `osascript`,
 * and macOS's own rotation ("Change picture every N minutes", Shuffle, a folder
 * of images) all change it without the shell hearing anything. The palette
 * therefore stayed on whichever image was last applied from inside the shell.
 *
 * macOS publishes no change notification for the desktop picture, so this
 * polls. One System Events query costs ~6ms of CPU, and the generator only runs
 * when the reported path differs from the one the current palette was built
 * from, so the steady state is just the query.
 */
Singleton {
    id: root

    property int pollInterval: 5000

    // The image colors.json was generated from. switchwall.sh writes this, so
    // it is also what the comparison resumes from after a restart.
    readonly property string themedWallpaper: Config.options?.background?.wallpaperPath ?? ""

    // An image the generator cannot read (a screen-saver desktop, a broken
    // file) would otherwise be retried on every tick forever. Each candidate
    // gets one attempt; a successful one lands in themedWallpaper anyway.
    property string lastAttempt: ""

    function load() {} // For forcing initialization

    Timer {
        // Same switch that gates the rest of wallpaper-derived theming.
        running: Config.ready && (Config.options?.appearance?.wallpaperTheming?.enableAppsAndShell ?? true)
        interval: root.pollInterval
        repeat: true
        triggeredOnStart: true // Catch a wallpaper changed while the shell was down
        onTriggered: if (!queryProc.running) queryProc.running = true
    }

    // System Events answers with an empty string for a solid-colour or
    // screen-saver desktop, and with the *containing directory* rather than the
    // current image while macOS's own picture rotation is on. Neither is
    // something to regenerate a palette from, so the path is filtered down to a
    // real file before it ever reaches QML.
    readonly property string queryScript: "p=$(osascript -e 'tell application \"System Events\" to get picture of current desktop' 2>/dev/null); [ -f \"$p\" ] && printf %s \"$p\""

    Process {
        id: queryProc
        command: ["bash", "-c", root.queryScript]
        stdout: StdioCollector {
            onStreamFinished: {
                const path = this.text.trim();
                if (path.length === 0) return;
                if (path === root.themedWallpaper || path === root.lastAttempt) return;
                root.lastAttempt = path;
                Quickshell.execDetached([
                    Directories.wallpaperSwitchScriptPath,
                    "--noswitch", // The desktop already shows it; only the palette is behind
                    "--image", path,
                ]);
            }
        }
    }
}
