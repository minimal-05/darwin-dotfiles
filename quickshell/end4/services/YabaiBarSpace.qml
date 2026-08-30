pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Cocoa
import QtQuick

/**
 * Keeps yabai's reserved screen area in step with the panels.
 *
 * On Wayland the compositor reads each layer surface's exclusive zone and keeps
 * windows out of it by itself. macOS has no such concept, so the Cocoa backend
 * sums the visible panels' exclusiveZone per edge into
 * Quickshell.Cocoa.Reservation and, once told to (below), writes yabai's
 * `external_bar all:<top>:<bottom>` itself whenever that changes: the bar, the
 * dock when pinned, a pinned sidebar, all from the zones they already declare,
 * and gone when they hide. This file no longer works those figures out again
 * from the config; it only adds the gap policy, which is the config's.
 *
 * What cannot be represented:
 * - external_bar has no left/right fields, so a vertical bar's reservation is
 *   folded into left_padding/right_padding here instead. That is weaker:
 *   external_bar shrinks yabai's idea of the display, so even a zoom-fullscreen
 *   window stays clear of it, while padding is only applied when tiling a
 *   space -- a zoom-fullscreen or native-fullscreen window will cover a
 *   vertical bar.
 * - Both knobs are global config, not per-display, so a bar shown on only some
 *   screens (bar.screenList) still reserves space on all of them; the backend
 *   publishes the largest reservation per edge across screens.
 * - autoHide with pushWindows on: the zone follows the bar as it slides in and
 *   out, as it does on Wayland, so yabai retiles the space each time.
 */
Singleton {
    id: root

    // Singletons are created lazily; shell.qml calls this to bring it up.
    function load() {}

    // The gap the user's windows keep from the screen edges. Matches
    // bin/qs-switch, which sets the same value before the shell starts. Every
    // edge gets it, the bar's own included on top of the reserved extent, so a
    // window sits the same distance from the bar as from the other three
    // sides -- including Hug, where the bar's corner curve then lands on that
    // strip of wallpaper instead of on the window.
    readonly property int gap: 8

    readonly property list<string> settings: [
        `top_padding ${root.gap}`,
        `bottom_padding ${root.gap}`,
        `left_padding ${Reservation.left + root.gap}`,
        `right_padding ${Reservation.right + root.gap}`,
        // yabairc seeds this too, for the desktop before the shell is up. Owned
        // here as well so the gap between two windows cannot drift away from
        // the gap around them.
        `window_gap ${root.gap}`
    ]
    readonly property string desired: root.settings.join(" | ")

    // The same numbers as HyprlandData reads back through `reserved`:
    // [left, top, right, bottom], the backend's per-edge zones plus the gap
    // -- external_bar (top/bottom) and the paddings (left/right) as applied.
    readonly property list<int> reserved: [
        Reservation.left + root.gap,
        Reservation.top + root.gap,
        Reservation.right + root.gap,
        Reservation.bottom + root.gap
    ]

    function apply(): void {
        // One shell so the settings land as a batch; `command -v` keeps this
        // quiet on a machine with no yabai installed.
        Quickshell.execDetached(["sh", "-c",
            "command -v yabai >/dev/null 2>&1 || exit 0; "
            + root.settings.map(s => `yabai -m config ${s}`).join("; ")
        ]);
        // This is the only writer of those settings, so the reader can be
        // told instead of asking yabai five times on every window event.
        HyprlandData.reserved = root.reserved;
    }

    // A vertical bar's reservation arrives as the bar shows and sizes; keep
    // yabai from retiling for the intermediate figure.
    Timer {
        id: applyTimer
        interval: 120
        repeat: false
        onTriggered: root.apply()
    }

    onDesiredChanged: applyTimer.restart()

    Component.onCompleted: {
        // external_bar is the backend's from here on. qs-switch sets a top-bar
        // reservation before launching the shell so the desktop is not left
        // with sketchybar's; the backend replaces it with the zones its panels
        // actually hold, and that is why the two do not fight.
        Reservation.applyToYabai = true
        root.apply()
    }
}
