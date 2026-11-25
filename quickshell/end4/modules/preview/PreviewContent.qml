import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel

/**
 * The image viewer. macOS hands a screenshot to Preview.app; this is the same
 * job in the shell's own Material styling, plus the two things a screenshot
 * actually needs before it goes anywhere: a pen and a crop. Anything past that
 * -- shapes, text, redaction, a format Qt cannot decode -- is still one button
 * away in Preview.app.
 */
Item {
    id: root

    property string path: ""
    signal closeRequested

    readonly property string fileName: root.path.split("/").pop()
    readonly property string directory: root.path.length > 0 ? FileUtils.parentDirectory(root.path) : ""

    readonly property list<string> imageExtensions: ["png", "jpg", "jpeg", "gif", "webp", "avif", "heic", "bmp", "tiff", "svg", "icns"]
    readonly property list<string> videoExtensions: ["mp4", "mov", "m4v"]

    function kindOf(path: string): string {
        const ext = path.split(".").pop().toLowerCase();
        return root.imageExtensions.includes(ext) ? "image" : root.videoExtensions.includes(ext) ? "video" : ext === "pdf" ? "pdf" : "";
    }

    // Markup and pixel zoom are image-only; video and pdf get their own view.
    readonly property string kind: root.kindOf(root.path)
    readonly property bool isImage: root.kind === "image"

    // Everything else in the folder, so the arrow keys walk a screenshot folder
    // the way Preview does.
    readonly property var siblings: {
        folderModel.count;
        folderModel.status;
        const out = [];
        for (let i = 0; i < folderModel.count; i++) {
            const p = FileUtils.trimFileProtocol(folderModel.get(i, "filePath"));
            if (root.kindOf(p).length > 0)
                out.push(p);
        }
        return out;
    }
    readonly property int index: root.siblings.indexOf(root.path)

    // 0 means "whatever fits". Any other value is a zoom the user asked for, and
    // it survives moving to the next image on purpose -- flipping through a
    // folder at 200% is the point of holding a zoom.
    property real userZoom: 0
    readonly property real fitZoom: (image.implicitWidth > 0 && image.implicitHeight > 0) ? Math.min(view.width / image.implicitWidth, view.height / image.implicitHeight, 1) : 1
    readonly property real zoom: root.userZoom > 0 ? root.userZoom : root.fitZoom

    function open(path: string): void {
        root.whenSaved(() => {
            root.clearEdits();
            root.path = path;
            root.userZoom = 0;
        });
    }

    // Drawings are kept, never dropped: every way of leaving an image --
    // closing the window, stepping to the next one, another file arriving --
    // comes through here and saves first. Undo is how not to keep a stroke.
    // The save is async (a grab, maybe a sips crop), so `then` waits for it.
    property var afterSave: null

    function whenSaved(then: var): void {
        if (root.saving) {
            root.afterSave = then;
            return;
        }
        if (!root.dirty || image.status !== Image.Ready) {
            then();
            return;
        }
        root.afterSave = then;
        root.saveEdits();
    }

    function step(delta: int): void {
        if (root.siblings.length === 0)
            return;
        const next = root.index + delta;
        if (next < 0 || next >= root.siblings.length)
            return;
        root.open(root.siblings[next]);
    }

    function zoomBy(factor: real): void {
        root.userZoom = Math.max(0.05, Math.min(16, root.zoom * factor));
    }

    // Finder over AppleScript rather than rm, the same bargain the file manager
    // makes: a delete from a picture viewer has to stay undoable.
    function trash(): void {
        if (root.path.length === 0)
            return;
        const next = root.siblings[root.index + 1] ?? root.siblings[root.index - 1] ?? "";
        // The same trash the file manager uses, so Put Back works on it too.
        Quickshell.execDetached(["python3", "-E", "-S", Directories.putBackScriptPath, "--trash", root.path]);
        root.clearEdits();
        if (next.length > 0)
            root.open(next);
        else
            root.closeRequested();
    }

    // --- markup --------------------------------------------------------------
    // Strokes and the crop live in image pixels, never screen pixels: the pen
    // and crop surfaces are the full-size image scaled down for display, so a
    // mark made at 40% zoom lands on the pixel it was drawn over. That also
    // makes the on-screen item the export item -- grabToImage renders the whole
    // subtree offscreen, image and strokes together, at whatever size is asked
    // for, so nothing has to composite by hand.
    property string tool: ""        // "", "pen", "crop"
    property var strokes: []        // [{ width, points: [x, y, x, y, ...] }]
    property var cropRect: null     // { x, y, w, h }
    property bool saving: false
    property point dragStart

    readonly property bool dirty: root.strokes.length > 0 || root.cropRect !== null
    readonly property color penColor: "#ff3b30"
    // A 4px line is a hair on a 6K screenshot and a slab on a 200px icon.
    readonly property real penWidth: Math.max(3, Math.min(24, image.implicitWidth / 400))

    // grabToImage always writes a PNG and takes its size in logical pixels, so
    // the target is divided back down by the ratio the screen will multiply in.
    readonly property string savePath: root.path.toLowerCase().endsWith(".png") ? root.path : `${FileUtils.trimFileExt(root.path)}.png`

    function setTool(name: string): void {
        root.tool = (root.tool === name ? "" : name);
    }

    function clearEdits(): void {
        root.strokes = [];
        root.cropRect = null;
        root.tool = "";
        overlay.redrawAll();
    }

    function undo(): void {
        if (root.strokes.length > 0)
            root.strokes = root.strokes.slice(0, -1);
        else
            root.cropRect = null;
        overlay.redrawAll();
    }

    function rectBetween(a: point, b: point): var {
        const x = Math.max(0, Math.min(a.x, b.x));
        const y = Math.max(0, Math.min(a.y, b.y));
        const x2 = Math.min(image.implicitWidth, Math.max(a.x, b.x));
        const y2 = Math.min(image.implicitHeight, Math.max(a.y, b.y));
        return {
            x: x,
            y: y,
            w: Math.max(0, x2 - x),
            h: Math.max(0, y2 - y)
        };
    }

    // saving=true hides the crop outline before the grab, so the guide does not
    // end up baked into the file it is a guide for.
    function saveEdits(): void {
        if (!root.dirty || root.saving || image.status !== Image.Ready)
            return;
        root.saving = true;
        const dpr = content.Screen.devicePixelRatio;
        content.grabToImage(result => root.writeGrab(result), Qt.size(image.implicitWidth / dpr, image.implicitHeight / dpr));
    }

    function writeGrab(result: var): void {
        const out = root.savePath;
        const c = root.cropRect;
        if (!c) {
            result.saveToFile(out);
            root.finishSave();
            return;
        }
        // sips is the crop: it is already on every Mac, and cropping pixels is
        // not worth a second render path.
        const tmp = `${out}.editing.png`;
        result.saveToFile(tmp);
        cropProcess.command = ["sips", "-c", `${Math.round(c.h)}`, `${Math.round(c.w)}`, "--cropOffset", `${Math.round(c.y)}`, `${Math.round(c.x)}`, tmp, "--out", out];
        cropProcess.running = true;
    }

    function finishSave(): void {
        const out = root.savePath;
        const wasPath = root.path;
        const after = root.afterSave;
        root.afterSave = null;
        root.saving = false;
        root.clearEdits();
        if (out !== wasPath) {
            root.open(out);
        } else {
            // cache is off, but the url has not changed, and an Image does not
            // re-read a file just because the bytes behind it did.
            root.path = "";
            root.path = wasPath;
        }
        if (after)
            after();
    }

    Process {
        id: cropProcess

        onExited: {
            Quickshell.execDetached(["rm", "-f", `${root.savePath}.editing.png`]);
            root.finishSave();
        }
    }

    focus: true

    Keys.onPressed: event => {
        switch (event.key) {
        case Qt.Key_Escape:
            // One escape puts the tool down -- abandoning a crop in progress,
            // keeping strokes -- the next closes the window, which saves them.
            if (root.tool.length > 0) {
                if (root.tool === "crop")
                    root.cropRect = null;
                root.tool = "";
            } else {
                root.closeRequested();
            }
            break;
        case Qt.Key_Left:
        case Qt.Key_Up:
            root.step(-1);
            break;
        case Qt.Key_Space:
            // Space is play/pause on a video, like QuickTime.
            if (root.kind === "video" && media.item)
                media.item.togglePlay();
            else
                root.step(1);
            break;
        case Qt.Key_Right:
        case Qt.Key_Down:
            root.step(1);
            break;
        case Qt.Key_Plus:
        case Qt.Key_Equal:
            root.zoomBy(1.25);
            break;
        case Qt.Key_Minus:
            root.zoomBy(1 / 1.25);
            break;
        case Qt.Key_0:
            root.userZoom = 0;
            break;
        case Qt.Key_1:
            root.userZoom = 1;
            break;
        case Qt.Key_Z:
            if (event.modifiers & Qt.ControlModifier)
                root.undo();
            break;
        case Qt.Key_S:
            if (event.modifiers & Qt.ControlModifier)
                root.saveEdits();
            break;
        default:
            return;
        }
        event.accepted = true;
    }

    FolderListModel {
        id: folderModel

        folder: root.directory.length > 0 ? Qt.resolvedUrl(root.directory) : ""
        showDirs: false
        showHidden: false
        sortField: FolderListModel.Name
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 8

        Toolbar {
            Layout.fillWidth: true
            // Same shorter bar the file manager uses: this is the top edge of a
            // window, not a floating dock.
            implicitHeight: 44
            padding: 4
            enableShadow: false

            IconToolbarButton {
                text: "chevron_left"
                enabled: root.index > 0
                downAction: () => root.step(-1)

                StyledToolTip {
                    text: Translation.tr("Previous")
                }
            }

            IconToolbarButton {
                text: "chevron_right"
                enabled: root.index >= 0 && root.index < root.siblings.length - 1
                downAction: () => root.step(1)

                StyledToolTip {
                    text: Translation.tr("Next")
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 6
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: root.dirty ? Translation.tr("%1 — edited").arg(root.fileName) : root.fileName
                    elide: Text.ElideMiddle
                    color: Appearance.colors.colOnLayer1
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.siblings.length > 1
                    text: `${root.index + 1} / ${root.siblings.length}`
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }

            IconToolbarButton {
                text: "draw"
                visible: root.isImage
                toggled: root.tool === "pen"
                enabled: image.status === Image.Ready
                downAction: () => root.setTool("pen")

                StyledToolTip {
                    text: Translation.tr("Draw")
                }
            }

            IconToolbarButton {
                text: "crop"
                visible: root.isImage
                toggled: root.tool === "crop"
                enabled: image.status === Image.Ready
                downAction: () => root.setTool("crop")

                StyledToolTip {
                    text: Translation.tr("Crop")
                }
            }

            IconToolbarButton {
                text: "undo"
                visible: root.dirty
                downAction: () => root.undo()

                StyledToolTip {
                    text: Translation.tr("Undo")
                }
            }

            IconToolbarButton {
                text: "save"
                visible: root.dirty
                enabled: !root.saving
                downAction: () => root.saveEdits()

                StyledToolTip {
                    text: Translation.tr("Save")
                }
            }

            IconToolbarButton {
                text: "zoom_out"
                visible: root.kind !== "video"
                downAction: () => root.zoomBy(1 / 1.25)

                StyledToolTip {
                    text: Translation.tr("Zoom out")
                }
            }

            StyledText {
                Layout.preferredWidth: 46
                visible: root.kind !== "video"
                horizontalAlignment: Text.AlignHCenter
                text: `${Math.round(root.zoom * 100)}%`
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }

            IconToolbarButton {
                text: "zoom_in"
                visible: root.kind !== "video"
                downAction: () => root.zoomBy(1.25)

                StyledToolTip {
                    text: Translation.tr("Zoom in")
                }
            }

            IconToolbarButton {
                text: "fit_screen"
                visible: root.isImage
                toggled: root.userZoom === 0
                downAction: () => root.userZoom = (root.userZoom === 0 ? 1 : 0)

                StyledToolTip {
                    text: root.userZoom === 0 ? Translation.tr("Actual size") : Translation.tr("Fit to window")
                }
            }

            IconToolbarButton {
                text: "delete"
                enabled: root.path.length > 0
                downAction: () => root.trash()

                StyledToolTip {
                    text: Translation.tr("Move to Trash")
                }
            }

            // The way out for anything this viewer deliberately does not do --
            // shapes, text, export, a format Qt cannot decode.
            IconToolbarButton {
                text: "open_in_new"
                downAction: () => Quickshell.execDetached(root.kind === "video" ? ["open", root.path] : ["open", "-a", "Preview", root.path])

                StyledToolTip {
                    text: root.kind === "video" ? Translation.tr("Open in QuickTime") : Translation.tr("Open in Preview")
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Appearance.rounding.large
            color: Appearance.colors.colLayer1
            clip: true

            Flickable {
                id: view

                anchors.fill: parent
                visible: root.isImage
                contentWidth: Math.max(view.width, image.implicitWidth * root.zoom)
                contentHeight: Math.max(view.height, image.implicitHeight * root.zoom)
                boundsBehavior: Flickable.StopAtBounds
                interactive: root.tool.length === 0 && (contentWidth > view.width || contentHeight > view.height)

                // Natural size with the zoom as a transform, rather than a
                // resized image: the markup layers inside then get to work in
                // image pixels and stay there.
                Item {
                    id: content

                    width: image.implicitWidth
                    height: image.implicitHeight
                    x: Math.max(0, (view.contentWidth - width * root.zoom) / 2)
                    y: Math.max(0, (view.contentHeight - height * root.zoom) / 2)

                    transform: Scale {
                        xScale: root.zoom
                        yScale: root.zoom
                    }

                    Image {
                        id: image

                        anchors.fill: parent
                        source: root.isImage ? `file://${encodeURI(root.path)}` : ""
                        // Full decode: this is the window you opened to look closely.
                        smooth: true
                        mipmap: true
                        asynchronous: true
                        cache: false
                    }

                    Canvas {
                        id: overlay

                        // Repainting a 6K surface on every mouse move is what
                        // makes a pen feel like a pen, so only the newest
                        // segment is drawn; a full redraw is for undo, which is
                        // not a per-frame event.
                        property bool fullRedraw: true

                        anchors.fill: parent
                        visible: root.strokes.length > 0 || root.tool === "pen"
                        renderTarget: Canvas.Image

                        // A canvas that has just appeared, or just been
                        // resized by a new image, has an empty buffer and no
                        // mouse event coming to fill it.
                        onVisibleChanged: overlay.redrawAll()
                        onWidthChanged: overlay.redrawAll()
                        onHeightChanged: overlay.redrawAll()

                        function redrawAll(): void {
                            overlay.fullRedraw = true;
                            overlay.requestPaint();
                        }

                        function style(ctx: var): void {
                            ctx.lineCap = "round";
                            ctx.lineJoin = "round";
                            ctx.strokeStyle = root.penColor;
                            ctx.fillStyle = root.penColor;
                        }

                        function drawStroke(ctx: var, s: var, from: int): void {
                            ctx.lineWidth = s.width;
                            // A tap is a dot; a zero-length path with a round
                            // cap draws nothing at all.
                            if (s.points.length === 2) {
                                ctx.beginPath();
                                ctx.arc(s.points[0], s.points[1], s.width / 2, 0, Math.PI * 2);
                                ctx.fill();
                                return;
                            }
                            ctx.beginPath();
                            ctx.moveTo(s.points[from], s.points[from + 1]);
                            for (let i = from + 2; i < s.points.length; i += 2)
                                ctx.lineTo(s.points[i], s.points[i + 1]);
                            ctx.stroke();
                        }

                        onPaint: {
                            const ctx = getContext("2d");
                            if (overlay.fullRedraw) {
                                ctx.clearRect(0, 0, overlay.width, overlay.height);
                                overlay.style(ctx);
                                overlay.fullRedraw = false;
                                for (const s of root.strokes)
                                    overlay.drawStroke(ctx, s, 0);
                                return;
                            }
                            overlay.style(ctx);
                            const last = root.strokes[root.strokes.length - 1];
                            if (last)
                                overlay.drawStroke(ctx, last, Math.max(0, last.points.length - 4));
                        }
                    }

                    // What the crop will keep. Hidden for the grab so the guide
                    // does not get saved into the picture.
                    Rectangle {
                        visible: root.cropRect !== null && !root.saving
                        x: root.cropRect ? root.cropRect.x : 0
                        y: root.cropRect ? root.cropRect.y : 0
                        width: root.cropRect ? root.cropRect.w : 0
                        height: root.cropRect ? root.cropRect.h : 0
                        color: "transparent"
                        border.width: Math.max(1, 2 / root.zoom)
                        border.color: root.penColor
                    }

                    // Inside the scaled item, so mouse coordinates arrive in
                    // image pixels with no conversion of their own.
                    MouseArea {
                        anchors.fill: parent
                        enabled: root.tool.length > 0
                        preventStealing: true
                        cursorShape: Qt.CrossCursor

                        onPressed: mouse => {
                            root.dragStart = Qt.point(mouse.x, mouse.y);
                            if (root.tool === "pen")
                                root.strokes = [...root.strokes, {
                                        width: root.penWidth,
                                        points: [mouse.x, mouse.y]
                                    }];
                            else
                                root.cropRect = null;
                            overlay.requestPaint();
                        }

                        onPositionChanged: mouse => {
                            if (root.tool === "pen")
                                // Growing the last stroke in place: the repaint
                                // is explicit anyway, and copying the whole
                                // stroke list per mouse move is not free.
                                root.strokes[root.strokes.length - 1].points.push(mouse.x, mouse.y);
                            else
                                root.cropRect = root.rectBetween(root.dragStart, Qt.point(mouse.x, mouse.y));
                            overlay.requestPaint();
                        }

                        onReleased: {
                            // A stray click in crop mode is a click, not a crop
                            // down to nothing.
                            if (root.tool === "crop" && root.cropRect && (root.cropRect.w < 8 || root.cropRect.h < 8))
                                root.cropRect = null;
                        }
                    }
                }

                // Wheel is zoom rather than scroll -- panning is a drag, and an
                // image viewer that scrolls a picture that already fits is just
                // a window that will not sit still.
                WheelHandler {
                    onWheel: event => {
                        root.zoomBy(event.angleDelta.y > 0 ? 1.1 : 1 / 1.1);
                        event.accepted = true;
                    }
                }

                TapHandler {
                    enabled: root.tool.length === 0
                    onDoubleTapped: root.userZoom = (root.userZoom === 0 ? 1 : 0)
                }
            }

            // Video and pdf, each in its own file so a screenshot never loads
            // QtMultimedia or QtPdf. Rebuilt per file with the path passed in at
            // creation: PdfScrollablePageView stays blank if its document's
            // source changes after it exists. Dropping the item on an image
            // also stops a video's sound.
            Loader {
                id: media

                anchors.fill: parent

                function reload(): void {
                    media.source = "";
                    if (root.kind === "video")
                        media.setSource("PreviewVideo.qml", { path: root.path });
                    else if (root.kind === "pdf")
                        media.setSource("PreviewPdf.qml", { path: root.path });
                }

                Connections {
                    target: root
                    function onPathChanged() {
                        media.reload();
                    }
                }
            }

            Binding {
                target: media.item
                property: "zoom"
                value: root.zoom
                when: root.kind === "pdf" && media.status === Loader.Ready
            }

            MaterialLoadingIndicator {
                anchors.centerIn: parent
                visible: image.status === Image.Loading
            }

            StyledText {
                anchors.centerIn: parent
                visible: image.status === Image.Error || root.path.length === 0 || media.status === Loader.Error
                text: root.path.length === 0 ? Translation.tr("Nothing open") : Translation.tr("Cannot show this file")
                color: Appearance.colors.colSubtext
            }
        }
    }
}
