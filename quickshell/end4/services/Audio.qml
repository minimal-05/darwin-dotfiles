pragma Singleton
pragma ComponentBehavior: Bound
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

/**
 * A nice wrapper for default Pipewire audio sink and source.
 */
Singleton {
    id: root

    // Misc props
    property bool ready: Pipewire.defaultAudioSink?.ready ?? false
    property PwNode sink: Pipewire.defaultAudioSink
    property PwNode source: Pipewire.defaultAudioSource
    readonly property real hardMaxValue: 2.00 // People keep joking about setting volume to 5172% so...
    property string audioTheme: Config.options.sounds.theme
    property real value: sink?.audio.volume ?? 0
    
    function friendlyDeviceName(node) {
        return (node.nickname || node.description || Translation.tr("Unknown"));
    }
    function appNodeDisplayName(node) {
        return (node.properties["application.name"] || node.description || node.name)
    }

    // Lists
    function correctType(node, isSink) {
        return (node.isSink === isSink) && node.audio
    }
    function appNodes(isSink) {
        return Pipewire.nodes.values.filter((node) => { // Should be list<PwNode> but it breaks ScriptModel
            return root.correctType(node, isSink) && node.isStream
        })
    }
    function devices(isSink) {
        return Pipewire.nodes.values.filter(node => {
            return root.correctType(node, isSink) && !node.isStream
        })
    }
    readonly property list<var> outputAppNodes: root.appNodes(true)
    readonly property list<var> inputAppNodes: root.appNodes(false)
    readonly property list<var> outputDevices: root.devices(true)
    readonly property list<var> inputDevices: root.devices(false)

    // Signals
    signal sinkProtectionTriggered(string reason);

    // Controls
    function toggleMute() {
        Audio.sink.audio.muted = !Audio.sink.audio.muted
    }

    function toggleMicMute() {
        Audio.source.audio.muted = !Audio.source.audio.muted
    }

    // Steps are spaced on a curve rather than evenly. Quiet is where you want
    // fine control; up loud, a couple of percent is inaudible. This gives about
    // 2 points per press near the bottom and 9 near the top, still 16 presses
    // end to end. `curve` is the knob: 1.0 is macOS's own even 1/16 notches,
    // higher stretches the quiet end further.
    //
    // bin/qs-volume repeats this formula for when the shell is not running.
    // Change the two together.
    readonly property real curve: 1.5
    readonly property int volumeSteps: 16

    function __volumeToStep(vol: real): real {
        return Math.pow(Math.max(0, Math.min(1, vol)), 1 / root.curve) * root.volumeSteps;
    }

    function __stepToVolume(n: real): real {
        return Math.pow(Math.max(0, Math.min(root.volumeSteps, n)) / root.volumeSteps, root.curve);
    }

    function stepVolume(dir: int) {
        if (!Audio.sink?.audio) return;
        const cur = Audio.value;
        const next = root.__stepToVolume(Math.round(root.__volumeToStep(cur)) + dir);
        // Volume is reported in whole percent, so a step smaller than one point
        // would round away and the press would do nothing. Only reachable if
        // `curve` is tuned up, but that is exactly when it would bite.
        // The old decrement also had no lower clamp and could go negative.
        const smallest = 0.01;
        Audio.sink.audio.volume = Math.abs(next - cur) < smallest
            ? Math.max(0, Math.min(1, cur + dir * smallest))
            : next;
    }

    // Single step. Scroll wheels and buttons use these, and they must never
    // start a ramp: nothing sends them a matching release.
    function incrementVolume() {
        root.stepVolume(1);
    }

    function decrementVolume() {
        root.stepVolume(-1);
    }

    // Holding a volume key has to repeat here, not upstream: Karabiner fires on
    // key-down only, and the consumer volume keys do not auto-repeat at all, so
    // holding one used to do exactly nothing. It now sends one call on press and
    // one on release, and this timer does the ramping in between.
    property int volumeRampDir: 0

    function startVolumeRamp(dir: int) {
        // The F-keys auto-repeat while the consumer volume keys do not, so a
        // hold arrives as either one press or a stream of them. Absorb the
        // extra presses; the ramp below already owns the repeat.
        if (volumeRamp.running && root.volumeRampDir === dir)
            return;
        root.volumeRampDir = dir;
        root.stepVolume(dir); // the press itself always steps once
        volumeRamp.ticks = 0;
        volumeRamp.interval = volumeRamp.startDelay;
        volumeRamp.restart();
    }

    function stopVolumeRamp() {
        volumeRamp.stop();
    }

    Timer {
        id: volumeRamp

        readonly property int startDelay: 400 // hold this long before repeating
        property int ticks: 0

        repeat: true
        interval: startDelay
        onTriggered: {
            interval = 90;
            // A key-up that never arrives must not ramp forever.
            if (++volumeRamp.ticks > 120) {
                volumeRamp.stop();
                return;
            }
            root.stepVolume(root.volumeRampDir);
        }
    }

    function setDefaultSink(node) {
        Pipewire.preferredDefaultAudioSink = node;
    }

    function setDefaultSource(node) {
        Pipewire.preferredDefaultAudioSource = node;
    }

    // Internals
    PwObjectTracker {
        objects: [sink, source]
    }

    Connections { // Protection against sudden volume changes
        target: sink?.audio ?? null
        property bool lastReady: false
        property real lastVolume: 0
        function onVolumeChanged() {
            if (!Config.options.audio.protection.enable) return;
            const newVolume = sink.audio.volume;
            // when resuming from suspend, we should not write volume to avoid pipewire volume reset issues
            if (isNaN(newVolume) || newVolume === undefined || newVolume === null) {
                lastReady = false;
                lastVolume = 0;
                return;
            }
            if (!lastReady) {
                lastVolume = newVolume;
                lastReady = true;
                return;
            }
            const maxAllowedIncrease = Config.options.audio.protection.maxAllowedIncrease / 100; 
            const maxAllowed = Config.options.audio.protection.maxAllowed / 100;

            if (newVolume - lastVolume > maxAllowedIncrease) {
                sink.audio.volume = lastVolume;
                root.sinkProtectionTriggered(Translation.tr("Illegal increment"));
            } else if (newVolume > maxAllowed || newVolume > root.hardMaxValue) {
                root.sinkProtectionTriggered(Translation.tr("Exceeded max allowed"));
                sink.audio.volume = Math.min(lastVolume, maxAllowed);
            }
            lastVolume = sink.audio.volume;
        }
    }

    // AirPlay output-switch notification. The default sink already reports
    // its transport (device.bus, from CoreAudioDevice::transport), so this
    // only has to react to `sink` changing -- no polling.
    property string __lastSinkTransport: ""
    property bool __sinkTracked: false

    function __checkAirplaySink() {
        const transport = root.sink?.properties?.["device.bus"] ?? "";
        if (root.__sinkTracked && transport !== root.__lastSinkTransport) {
            if (transport === "airplay")
                Quickshell.execDetached(["notify-send", "AirPlay", `Now playing on ${root.sink.description}`, "-a", "AirPlay"]);
            else if (root.__lastSinkTransport === "airplay")
                Quickshell.execDetached(["notify-send", "AirPlay", "Switched off AirPlay", "-a", "AirPlay"]);
        }
        root.__lastSinkTransport = transport;
        root.__sinkTracked = true;
    }

    onSinkChanged: root.__checkAirplaySink()

    // macOS ships no freedesktop sound theme under /usr/share/sounds and no
    // ffplay. The stock alert sounds are /System/Library/Sounds/*.aiff and
    // afplay is part of the base install, so the names end-4 uses are mapped
    // onto those.
    readonly property var systemSoundNames: ({
        "dialog-warning": "Basso",
        "dialog-error": "Basso",
        "dialog-information": "Tink",
        "suspend-error": "Sosumi",
        "complete": "Glass",
        "power-plug": "Bottle",
        "power-unplug": "Pop",
        "alarm-clock-elapsed": "Submarine",
        "bell": "Ping",
        "message": "Ping",
        "device-added": "Tink",
        "device-removed": "Tink"
    })

    function playSystemSound(soundName) {
        // sounds.theme names a freedesktop theme, which has no macOS analogue;
        // an unmapped name is passed through so a stock macOS sound also works.
        const macSound = root.systemSoundNames[soundName] ?? soundName;
        Quickshell.execDetached([
            "afplay",
            `/System/Library/Sounds/${macSound}.aiff`
        ]);
    }

    // External trigger points. On Linux the volume keys reach these through
    // Hyprland's GlobalShortcut protocol; on macOS Karabiner grabs the media
    // keys before the system sees them and calls in over IPC instead, which is
    // also what keeps macOS from drawing its own volume HUD.
    IpcHandler {
        target: "audio"

        // Key-down. Steps once immediately, then ramps if the key is held
        // until release() arrives.
        function increment() {
            root.startVolumeRamp(1);
        }

        function decrement() {
            root.startVolumeRamp(-1);
        }

        function mute() {
            root.toggleMute();
        }

        // Sent on key-up, ending a hold started by increment/decrement.
        function release() {
            root.stopVolumeRamp();
        }
    }
}
