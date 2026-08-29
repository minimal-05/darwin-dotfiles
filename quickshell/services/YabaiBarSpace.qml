pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import Quickshell
import QtQuick

/**
 * Keeps yabai's reserved screen area in step with the bar.
 *
 * On Wayland the compositor reads the layer surface's exclusive zone and keeps
 * windows out of it by itself, so upstream only has to set `exclusiveZone` on
 * the bar's PanelWindow. macOS has no such concept and quickshell's Cocoa
 * windows are plain overlays, so the shell has to tell the window manager
 * itself. yabai's whole vocabulary for this is
 * `external_bar all:<top>:<bottom>` plus the four `*_padding` values.
 *
 * What cannot be represented:
 * - external_bar has no left/right fields, so a vertical bar is expressed with
 *   left_padding/right_padding instead. That is weaker: external_bar shrinks
 *   yabai's idea of the display, so even a zoom-fullscreen window stays clear
 *   of it, while padding is only applied when tiling a space -- a
 *   zoom-fullscreen or native-fullscreen window will cover a vertical bar.
 * - Both knobs are global config, not per-display, so a bar shown on only some
 *   screens (bar.screenList) still reserves space on all of them.
 * - autoHide with pushWindows on: on Wayland the exclusive zone grows and
 *   shrinks as the bar slides in and out. Doing that here would make yabai
 *   retile every window on the screen on every hover, so the space is reserved
 *   permanently instead -- pushWindows means "windows never sit under the bar",
 *   not "windows move when it appears".
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

    readonly property bool vertical: Config.options.bar.vertical
    // bar.bottom doubles as "right" for a vertical bar -- see the anchors in
    // modules/verticalBar/VerticalBar.qml.
    readonly property bool farSide: Config.options.bar.bottom

    // Same expression as the bar's own exclusiveZone binding.
    readonly property int extent: (root.vertical ? Appearance.sizes.baseVerticalBarWidth : Appearance.sizes.baseBarHeight)
        + (Config.options.bar.cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0)

    readonly property bool reserving: GlobalStates.barOpen
        && !(Config.options.bar.autoHide.enable && !Config.options.bar.autoHide.pushWindows)

    readonly property bool atTop: !root.vertical && !root.farSide && root.reserving
    readonly property bool atBottom: !root.vertical && root.farSide && root.reserving
    readonly property bool atLeft: root.vertical && !root.farSide && root.reserving
    readonly property bool atRight: root.vertical && root.farSide && root.reserving

    readonly property list<string> settings: [
        `external_bar all:${root.atTop ? root.extent : 0}:${root.atBottom ? root.extent : 0}`,
        `top_padding ${root.gap}`,
        `bottom_padding ${root.gap}`,
        `left_padding ${root.atLeft ? root.extent + root.gap : root.gap}`,
        `right_padding ${root.atRight ? root.extent + root.gap : root.gap}`,
        // yabairc seeds this too, for the desktop before the shell is up. Owned
        // here as well so the gap between two windows cannot drift away from
        // the gap around them.
        `window_gap ${root.gap}`
    ]
    readonly property string desired: root.settings.join(" | ")

    // The same numbers as HyprlandData reads back through `reserved`:
    // [left, top, right, bottom] with external_bar folded into top/bottom.
    readonly property list<int> reserved: [
        root.atLeft ? root.extent + root.gap : root.gap,
        (root.atTop ? root.extent : 0) + root.gap,
        root.atRight ? root.extent + root.gap : root.gap,
        (root.atBottom ? root.extent : 0) + root.gap
    ]

    function apply(): void {
        if (!Platform.isMacOS)
            return;
        // One shell so the five settings land as a batch; `command -v` keeps
        // this quiet on a machine with no yabai installed.
        Quickshell.execDetached(["sh", "-c",
            "command -v yabai >/dev/null 2>&1 || exit 0; "
            + root.settings.map(s => `yabai -m config ${s}`).join("; ")
        ]);
        // This is the only writer of those settings, so the reader can be
        // told instead of asking yabai five times on every window event.
        HyprlandData.reserved = root.reserved;
    }

    // The settings window writes the config key by key, so a bar-position
    // change can arrive as two separate writes (bottom, then vertical).
    // Debouncing keeps yabai from retiling for the intermediate position.
    Timer {
        id: applyTimer
        interval: 120
        repeat: false
        onTriggered: root.apply()
    }

    onDesiredChanged: applyTimer.restart()

    // qs-switch sets a top-bar reservation before launching the shell so the
    // desktop is not left with sketchybar's; this corrects it for whatever the
    // config actually says, and is why the two do not fight.
    Component.onCompleted: root.apply()
}
