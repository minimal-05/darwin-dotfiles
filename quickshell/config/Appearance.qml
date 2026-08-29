pragma Singleton

import QtQuick
import Quickshell

// Material 3 dark baseline, carried over from the SketchyBar config so the
// shell stays visually continuous with the rest of the setup (kitty included).
Singleton {
    id: root

    readonly property QtObject colors: QtObject {
        readonly property color bar: "#f0141218"          // surface, translucent
        readonly property color popup: "#ff211F26"        // surface container low
        readonly property color pill: "#ff2B2930"         // surface container
        readonly property color hover: "#ff3B3846"        // pill + 8% onSurface state layer
        readonly property color primary: "#ffD0BCFF"
        readonly property color primaryFg: "#ff381E72"
        readonly property color secondary: "#ffCCC2DC"
        readonly property color secContainer: "#ff4A4458"
        readonly property color tertiary: "#ffEFB8C8"     // clock accent
        readonly property color surfaceFg: "#ffE6E0E9"
        readonly property color muted: "#ffCAC4D0"        // on surface variant
        readonly property color outline: "#ff49454F"
        readonly property color red: "#ffF2B8B5"
        readonly property color green: "#ffA8D5A2"
        readonly property color yellow: "#ffE8C48A"
        readonly property color blue: "#ffA8C7FA"
        readonly property color teal: "#ff8FD5CB"
    }

    readonly property QtObject font: QtObject {
        // Same families the SketchyBar config used, so glyph coverage is a known
        // quantity — these are the Nerd Font Material Design codepoints and only
        // a patched font carries them.
        readonly property string sans: "ComicShannsMono Nerd Font"
        readonly property string mono: "Maple Mono NF"

        // Symbols Nerd Font rather than a patched programming font: Nerd Fonts
        // v3 trimmed the Material Design range out of the patched builds, so
        // half these codepoints fell back to colour emoji. The symbols-only
        // build keeps the full set.
        readonly property string icon: "Symbols Nerd Font"

        readonly property int small: 11
        readonly property int normal: 13
        readonly property int large: 15
        readonly property int iconSize: 15
    }

    readonly property QtObject sizes: QtObject {
        readonly property int barHeight: 38
        readonly property int barMargin: 8
        readonly property int barRadius: 18
        readonly property int pillRadius: 12
        readonly property int pillHeight: 26
        readonly property int gap: 8
        readonly property int padding: 10
    }

    // Material 3 expressive motion. Spatial moves use an overshooting curve,
    // colour and opacity use a plain ease so they never look springy.
    readonly property QtObject anim: QtObject {
        readonly property int instant: 100
        readonly property int color: 200
        readonly property int spatial: 350
        readonly property int slow: 500

        readonly property var emphasized: [0.2, 0, 0, 1, 1, 1]
        readonly property var standard: [0.3, 0, 0.8, 0.15, 1, 1]
    }
}
