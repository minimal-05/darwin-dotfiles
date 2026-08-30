pragma Singleton
pragma ComponentBehavior: Bound

// From https://github.com/caelestia-dots/shell with modifications.
// License: GPLv3

import qs.modules.common
import qs.modules.common.functions
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick

/**
 * For managing brightness of monitors.
 *
 * macOS port: the internal display's backlight is read/set through the
 * private DisplayServices framework via scripts/macos/brightness.py (ctypes,
 * no extra install required) -- the Homebrew `brightness` tool uses the
 * deprecated IODisplay API and fails on Apple Silicon internal panels with
 * kIOReturnUnsupported. External-monitor brightness over DDC/CI has no
 * built-in macOS tool (would need `brew install m1ddc`), so DDC support is
 * dropped entirely rather than ported: ddcMonitors stays permanently empty
 * and every monitor is treated as the non-DDC case.
 */
Singleton {
    id: root
    signal brightnessChanged()

    property var ddcMonitors: []
    readonly property list<BrightnessMonitor> monitors: Quickshell.screens.map(screen => monitorComp.createObject(root, {
        screen
    }))

    function getMonitorForScreen(screen: ShellScreen): var {
        return monitors.find(m => m.screen === screen);
    }

    // The gamma fallback upstream puts below-zero dimming on these keys, but
    // Hyprsunset.setGamma shells out to hyprctl, which does not exist here. It
    // is dropped rather than ported, the same way DDC is: on macOS 0 is simply
    // the bottom, the backlight goes off, and the next press brings it back --
    // which is what the native keys do anyway.
    // Which display a brightness key should act on. Upstream asks the compositor
    // for the focused monitor; here that is the yabai-backed shim, so with yabai
    // stopped -- or before it has answered its first query -- focusedMonitor is
    // null, find() returns undefined and the key silently does nothing. A
    // brightness key has to work whether or not a window manager is running, so
    // fall back to the only monitor when there is one, then to the first.
    function targetMonitor(): var {
        const focusedName = Hyprland.focusedMonitor?.name ?? "";
        const focused = focusedName.length > 0
            ? monitors.find(m => focusedName === m.screen.name)
            : undefined;
        return focused ?? monitors[0] ?? null;
    }

    function increaseBrightness(): void {
        const monitor = root.targetMonitor();
        if (monitor)
            monitor.setBrightness(monitor.brightness + 0.05);
    }

    function decreaseBrightness(): void {
        const monitor = root.targetMonitor();
        if (monitor)
            monitor.setBrightness(monitor.brightness - 0.05); // setBrightness clamps at 0
    }

    reloadableId: "brightness"

    onMonitorsChanged: {
        // No DDC probing on macOS -- ddcMonitors stays empty, so every
        // BrightnessMonitor.initialize() below resolves to the DisplayServices path.
        ddcMonitors = [];
        initializeMonitor(0);
    }

    function initializeMonitor(i: int): void {
        if (i >= monitors.length)
            return;
        monitors[i].initialize();
    }

    Process {
        id: setProc
    }

    component BrightnessMonitor: QtObject {
        id: monitor

        required property ShellScreen screen
        property bool isDdc
        property string busNum
        property int rawMaxBrightness: 100
        property real brightness
        property real brightnessMultiplier: 1.0
        property real multipliedBrightness: Math.max(0, Math.min(1, brightness * (Config.options.light.antiFlashbang.enable ? brightnessMultiplier : 1)))
        property bool ready: false
        property bool animateChanges: !monitor.isDdc

        onBrightnessChanged: {
            if (!monitor.ready) return;
            root.brightnessChanged();
        }

        Behavior on multipliedBrightness {
            enabled: monitor.animateChanges
            NumberAnimation {
                duration: 200
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveEffects
            }
        }
        onMultipliedBrightnessChanged: {
            if (monitor.animationEnabled) syncBrightness();
            else setTimer.restart();
        }

        function initialize() {
            monitor.ready = false;
            // No DDC/CI on macOS -- see the Singleton doc comment above. Every
            // monitor takes the DisplayServices path via brightness.py.
            isDdc = false;
            busNum = "";
            initProc.command = ["python3", Directories.brightnessScriptPath, "get"];
            initProc.running = true;
        }

        readonly property Process initProc: Process {
            stdout: SplitParser {
                onRead: data => {
                    const value = parseFloat(data);
                    if (!isNaN(value))
                        monitor.brightness = value;
                    monitor.ready = true;
                }
            }
            onExited: (exitCode, exitStatus) => {
                initializeMonitor(root.monitors.indexOf(monitor) + 1);
            }
        }

        property var setTimer: Timer {
            id: setTimer
            interval: 30
            onTriggered: {
                syncBrightness();
            }
        }

        function syncBrightness() {
            // One write at a time. Each `set` is a ~165ms python3 spawn while the
            // animation asks for a new value every frame, so intermediate frames
            // are dropped and the newest value is sent once the write in flight
            // finishes. Without this the backlight lags the key by seconds.
            if (setProc.running) {
                setTimer.restart();
                return;
            }
            const brightnessValue = Math.max(monitor.multipliedBrightness, 0);
            // 0 really means backlight off, matching what native macOS does at
            // the bottom of the F1 range. The old brightnessctl "0% -> 1%" guard
            // is dropped: this is recoverable here, F2 brings the panel back.
            setProc.exec(["python3", Directories.brightnessScriptPath, "set", brightnessValue.toFixed(4)]);
        }

        function setBrightness(value: real): void {
            value = Math.max(0, Math.min(1, value));
            monitor.brightness = value;
        }

        function setBrightnessMultiplier(value: real): void {
            monitor.brightnessMultiplier = value;
        }
    }

    Component {
        id: monitorComp

        BrightnessMonitor {}
    }

    // Anti-flashbang
    property int workspaceAnimationDelay: 500
    property int contentSwitchDelay: 30
    property string screenshotDir: "/tmp/quickshell/brightness/antiflashbang"
    function brightnessMultiplierForLightness(x: real): real {
        // I hand picked some values and fitted an exponential curve for this
        // 6.600135 + 216.360356 * e^(-0.0811129189x)
        // Division by 100 is to normalize to [0, 1]
        return (6.600135 + 216.360356 * Math.pow(Math.E, -0.0811129189 * x)) / 100.0;
    }
    Variants {
        model: Quickshell.screens
        Scope {
            id: screenScope
            required property var modelData
            property string screenName: modelData.name
            property string screenshotPath: `${root.screenshotDir}/screenshot-${screenName}.png`
            Connections {
                enabled: Config.options.light.antiFlashbang.enable && Appearance.m3colors.darkmode
                target: Hyprland
                function onRawEvent(event) {
                    if (["activewindowv2", "windowtitlev2"].includes(event.name)) {
                        screenshotTimer.interval = root.contentSwitchDelay;
                        screenshotTimer.restart();
                    } else if (["workspacev2"].includes(event.name)) {
                        screenshotTimer.interval = root.workspaceAnimationDelay;
                        screenshotTimer.restart();
                    }
                }
            }

            Timer {
                id: screenshotTimer
                interval: 700 // This is what I have for a Hyprland ws anim
                onTriggered: {
                    screenshotProc.running = false;
                    screenshotProc.running = true;
                }
            }

            Process {
                id: screenshotProc
                command: ["bash", "-c",
                    `mkdir -p '${StringUtils.shellSingleQuoteEscape(root.screenshotDir)}'`
                    + ` && grim -o '${StringUtils.shellSingleQuoteEscape(screenScope.screenName)}' -`
                    + ` | magick png:- -colorspace Gray -format "%[fx:mean*100]" info:`
                ]
                stdout: StdioCollector {
                    id: lightnessCollector
                    onStreamFinished: {
                        Quickshell.execDetached(["rm", screenScope.screenshotPath]); // Cleanup
                        const lightness = lightnessCollector.text
                        const newMultiplier = root.brightnessMultiplierForLightness(parseFloat(lightness))
                        Brightness.getMonitorForScreen(screenScope.modelData).setBrightnessMultiplier(newMultiplier)
                    }
                }
            }
        }
    }

    // External trigger points

    IpcHandler {
        target: "brightness"

        // Key-down. Steps once immediately, then ramps if the key is held
        // until release() arrives.
        function increment() {
            root.startBrightnessRamp(1);
        }

        function decrement() {
            root.startBrightnessRamp(-1);
        }

        // Sent on key-up, ending a hold started by increment/decrement.
        function release() {
            root.stopBrightnessRamp();
        }
    }

    // Same shape as the volume ramp in Audio.qml, for the same reason:
    // Karabiner fires on key-down only, so a hold arrives as one press and one
    // release, and this timer fills in the repeat between them.
    property int brightnessRampDir: 0

    function focusedBrightness(): real {
        const monitor = root.targetMonitor();
        return monitor ? monitor.brightness : -1;
    }

    function stepBrightness(dir: int): void {
        if (dir > 0)
            root.increaseBrightness();
        else
            root.decreaseBrightness();
    }

    function startBrightnessRamp(dir: int): void {
        // The F-keys auto-repeat, so a hold can arrive as a stream of presses.
        // Absorb the extras; the ramp below already owns the repeat.
        if (brightnessRamp.running && root.brightnessRampDir === dir)
            return;
        root.brightnessRampDir = dir;
        root.stepBrightness(dir); // the press itself always steps once
        brightnessRamp.ticks = 0;
        brightnessRamp.interval = brightnessRamp.startDelay;
        brightnessRamp.restart();
    }

    function stopBrightnessRamp(): void {
        brightnessRamp.stop();
    }

    Timer {
        id: brightnessRamp

        readonly property int startDelay: 400 // hold this long before repeating
        property int ticks: 0

        repeat: true
        interval: startDelay
        onTriggered: {
            interval = 90;
            // A key-up that never arrives must not ramp forever.
            if (++brightnessRamp.ticks > 120) {
                brightnessRamp.stop();
                return;
            }
            const before = root.focusedBrightness();
            root.stepBrightness(root.brightnessRampDir);
            // Both rails leave brightness untouched. Stop there rather than
            // ramping on into the gamma fallback, which is not what the key does
            // natively -- black is the bottom.
            if (root.focusedBrightness() === before)
                brightnessRamp.stop();
        }
    }

    GlobalShortcut {
        name: "brightnessIncrease"
        description: "Increase brightness"
        onPressed: root.increaseBrightness()
    }

    GlobalShortcut {
        name: "brightnessDecrease"
        description: "Decrease brightness"
        onPressed: root.decreaseBrightness()
    }
}
