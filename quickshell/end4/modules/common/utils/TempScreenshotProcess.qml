import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

Process {
    id: screenshotProc
    running: true
    property string screenshotDir: Directories.screenshotTemp
    required property ShellScreen screen
    property string screenshotPath: `${screenshotDir}/image-${screen.name}`
    // macOS has no grim. `screencapture -R` takes a rect in logical points of the
    // global display space, so the screen's own geometry picks out exactly one
    // display, and it writes physical (Retina) pixels — the same scale factor
    // consumers already multiply by before cropping.
    command: ["bash", "-c", `mkdir -p '${StringUtils.shellSingleQuoteEscape(screenshotDir)}' && screencapture -x -R${Math.round(screen.x)},${Math.round(screen.y)},${Math.round(screen.width)},${Math.round(screen.height)} '${StringUtils.shellSingleQuoteEscape(screenshotPath)}'`]
}
