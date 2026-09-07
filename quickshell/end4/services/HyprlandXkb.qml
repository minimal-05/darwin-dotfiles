pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * The keyboard layout names for the bar and lock screen indicators, read
 * once from the hyprctl stand-in's `devices`, which lists the enabled macOS
 * input sources with the selected one as active_keymap.
 */
Singleton {
    id: root
    property list<string> layoutCodes: []
    property string currentLayoutCode: ""

    Process {
        running: true
        command: ["hyprctl", "-j", "devices"]
        stdout: StdioCollector {
            id: devicesCollector
            onStreamFinished: {
                const keyboard = JSON.parse(devicesCollector.text).keyboards.find(kb => kb.main);
                root.layoutCodes = keyboard.layout.split(",").filter(name => name.length > 0);
                root.currentLayoutCode = keyboard.active_keymap;
            }
        }
    }
}
