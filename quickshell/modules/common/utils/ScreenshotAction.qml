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

    property string imageSearchEngineBaseUrl: Config.options.search.imageSearch.imageSearchEngineBaseUrl
    property string fileUploadApiEndpoint: "https://uguu.se/upload"

    function getCommand(x, y, width, height, screenshotPath, action, saveDir = "") {
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
        const slurpRegion = `${rx},${ry} ${rw}x${rh}`
        const uploadAndGetUrl = (filePath) => {
            return `curl -sF files[]=@'${StringUtils.shellSingleQuoteEscape(filePath)}' ${root.fileUploadApiEndpoint} | jq -r '.files[0].url'`
        }
        // The file path arrives as argv so no quoting of it leaks into AppleScript.
        const copyImage = (shellPath) => `osascript -e 'on run argv
set the clipboard to (read (POSIX file (item 1 of argv)) as «class PNGf»)
end run' ${shellPath}`
        switch (action) {
            case ScreenshotAction.Action.Copy:
                if (saveDir === "") {
                    // not saving the screenshot, just copy to clipboard
                    return ["bash", "-c", `${cropInPlace} && ${copyImage(shot)} && ${cleanup}`]
                    break;
                }
                return [
                    "bash", "-c",
                    `saveDir='${StringUtils.shellSingleQuoteEscape(saveDir)}' && \
                    mkdir -p "$saveDir" && \
                    savePath="$saveDir/screenshot-$(date '+%Y-%m-%d_%H.%M.%S').png" && \
                    ${cropInPlace} && \
                    cp ${shot} "$savePath" && \
                    ${copyImage('"$savePath"')} && \
                    ${cleanup}`
                ]

                break;
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
