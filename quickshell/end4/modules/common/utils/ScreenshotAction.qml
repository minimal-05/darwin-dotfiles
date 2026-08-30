pragma ComponentBehavior: Bound
pragma Singleton
import qs.modules.common
import qs.modules.common.utils
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import Qt.labs.synchronizer
import Quickshell

Singleton {
    id: root

    enum Action {
        Copy,
        Edit,
        Search,
        CharRecognition,
        Record,
        RecordWithSound
    }

    // shell.qml sets QT_SCALE_FACTOR, which makes one QML unit that many OS
    // points. Everything that crops works in physical pixels and never notices;
    // `screencapture -R` is in points, so the recording rect has to convert.
    readonly property real uiScale: parseFloat(Quickshell.env("QT_SCALE_FACTOR") ?? "1") || 1

    property string imageSearchEngineBaseUrl: Config.options.search.imageSearch.imageSearchEngineBaseUrl
    property string fileUploadApiEndpoint: "https://uguu.se/upload"

    // The file path arrives as argv so no quoting of it leaks into AppleScript.
    function copyImageCommand(shellPath) {
        return `osascript -e 'on run argv
set the clipboard to (read (POSIX file (item 1 of argv)) as «class PNGf»)
end run' ${shellPath}`
    }

    // Whole-display shot with no selector, for the cmd+shift+3 binding.
    // screencapture with a single output path takes the main display, and -x
    // keeps Apple's shutter sound and floating thumbnail out of it -- the corner
    // thumbnail is ours now, see modules/captureShelf.
    //
    // The shot is written to the temp dir and moved into the shelf in one
    // rename, so the shelf's directory watcher never sees a half-written file.
    // Where it ends up after that is the shelf's decision, not this command's.
    function getFullscreenCommand() {
        const dir = StringUtils.shellSingleQuoteEscape(Directories.screenshotTemp)
        const shelf = StringUtils.shellSingleQuoteEscape(Directories.captureShelf)
        return ["bash", "-c", `mkdir -p '${dir}' '${shelf}' && \
            shot='${dir}/fullscreen.png' && \
            screencapture -x "$shot" && \
            ${root.copyImageCommand('"$shot"')} && \
            mv "$shot" '${shelf}'/screenshot-"$(date '+%Y-%m-%d_%H.%M.%S')".png`]
    }

    function getCommand(x, y, width, height, screenshotPath, action, scale = 1) {
        // Set command for action
        const rx = Math.round(x);
        const ry = Math.round(y);
        const rw = Math.round(width);
        const rh = Math.round(height);
        // macOS: `magick` is present (brew), so cropping is unchanged. Everything
        // downstream of the crop is not: there is no wl-copy, no xdg-open and no
        // satty/swappy. The pasteboard only takes image *data* through
        // AppleScript, which means the crop has to land in a file first rather
        // than being piped, so every branch below crops in place.
        const shot = `'${StringUtils.shellSingleQuoteEscape(screenshotPath)}'`
        const cropInPlace = `magick ${shot} -crop ${rw}x${rh}+${rx}+${ry} +repage png:${shot}`
        const cleanup = `rm -f ${shot}`
        const shelf = StringUtils.shellSingleQuoteEscape(Directories.captureShelf)
        // One rename into the shelf: atomic, so the watcher only ever sees a
        // finished file. The crop is still copied to the pasteboard on the way
        // past -- the thumbnail is for dragging, not a replacement for cmd+v.
        const moveToShelf = `mkdir -p '${shelf}' && mv ${shot} '${shelf}'/screenshot-"$(date '+%Y-%m-%d_%H.%M.%S')".png`
        // `screencapture -R` takes OS points, but the crop above works in
        // physical pixels, so the recording rect divides the monitor scale back
        // out and re-applies the UI scale.
        // ponytail: monitor-relative — a second display's rect would need its
        // origin added on top.
        const toPoints = (v) => Math.round(v / scale * root.uiScale);
        const slurpRegion = `${toPoints(x)},${toPoints(y)} ${toPoints(width)}x${toPoints(height)}`
        const uploadAndGetUrl = (filePath) => {
            return `curl -sF files[]=@'${StringUtils.shellSingleQuoteEscape(filePath)}' ${root.fileUploadApiEndpoint} | jq -r '.files[0].url'`
        }
        const copyImage = root.copyImageCommand;
        switch (action) {
            case ScreenshotAction.Action.Copy:
                return ["bash", "-c", `${cropInPlace} && ${copyImage(shot)} && ${moveToShelf}`]
            case ScreenshotAction.Action.Edit:
                // Stand-in for satty/swappy: Preview's Markup tools are the closest
                // built-in annotator. The crop is moved out of the temp path first
                // so the next selection does not overwrite what is being edited.
                return ["bash", "-c", `${cropInPlace} && \
                    editPath="$(dirname ${shot})/screenshot-$(date '+%Y-%m-%d_%H.%M.%S').png" && \
                    mv ${shot} "$editPath" && \
                    open -a Preview "$editPath"`]
                break;
            case ScreenshotAction.Action.Search:
                return ["bash", "-c", `${cropInPlace} && open "${root.imageSearchEngineBaseUrl}$(${uploadAndGetUrl(screenshotPath)})" && ${cleanup}`]
                break;
            case ScreenshotAction.Action.CharRecognition:
                // tesseract is not installed and has no macOS built-in equivalent
                // reachable from the shell; the pipe is ported anyway so that a
                // brew-installed tesseract works.
                return ["bash", "-c", `${cropInPlace} && tesseract ${shot} stdout -l $(tesseract --list-langs | awk 'NR>1{print $1}' | tr '\\n' '+' | sed 's/\\+$/\\n/') | pbcopy && ${cleanup}`]
                break;
            case ScreenshotAction.Action.Record:
                return ["bash", "-c", `${Directories.recordScriptPath} --region '${slurpRegion}'`]
                break;
            case ScreenshotAction.Action.RecordWithSound:
                return ["bash", "-c", `${Directories.recordScriptPath} --region '${slurpRegion}' --sound`]
                break;
            default:
                console.warn("[Region Selector] Unknown snip action, skipping snip.");
                return;
        }
    }
}
