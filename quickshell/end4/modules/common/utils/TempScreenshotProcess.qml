import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.utils

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
    //
    // Points are not QML units, though: QT_SCALE_FACTOR is the whole difference.
    // On the primary display an oversized rect is clamped back to the same
    // display and nothing shows; on a second one the origin is not 0,0 and the
    // shot lands on the wrong pixels.
    function toPoints(v: real): int {
        return Math.round(v * ScreenshotAction.uiScale);
    }
    command: ["bash", "-c", `mkdir -p '${StringUtils.shellSingleQuoteEscape(screenshotDir)}' && screencapture -x -R${screenshotProc.toPoints(screen.x)},${screenshotProc.toPoints(screen.y)},${screenshotProc.toPoints(screen.width)},${screenshotProc.toPoints(screen.height)} '${StringUtils.shellSingleQuoteEscape(screenshotPath)}'`]
}
