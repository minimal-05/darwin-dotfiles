pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import Qt.labs.folderlistmodel
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

/**
 * The corner shelf: where a fresh screenshot or recording waits before it is
 * filed, the way macOS's own capture thumbnail does.
 *
 * A finished capture is moved into Directories.captureShelf and its thumbnail
 * slides into the bottom right corner. From there it leaves one of two ways:
 *
 * - Dragged out, into anything that takes a file. That is a real platform drag,
 *   so the receiving app gets the file itself, and the shelf copy is deleted --
 *   the capture never reaches the desktop, which is the point.
 * - Ignored. After a few seconds it slides off the edge and files itself:
 *   screenshots to the desktop, recordings to ~/Movies.
 *
 * The shelf directory *is* the state. There is no queue to keep in sync: the
 * directory model is the list, one delegate is one pending capture, and the file
 * existing is what "pending" means. So a capture that arrives while the shell is
 * reloading is picked up on the next start rather than lost, and every producer
 * -- the region selector, cmd+shift+3, record.sh, a stray `mv` from a terminal
 * -- gets a thumbnail without knowing this file exists.
 *
 * Producers write elsewhere and rename in. A capture must appear in the shelf
 * complete, in one atomic rename, or the watcher raises a thumbnail of a
 * half-written file; recordings, which are written in place over minutes, sit
 * under a hidden name until they are done.
 */
Scope {
    id: root

    // About what Apple gives its thumbnail: long enough to reach for, short
    // enough that it is not sitting on top of what you just captured.
    readonly property int lingerMs: 5000
    readonly property int cardWidth: 232
    readonly property int cardHeight: 146
    // How far a card travels on its way in and out. It ends up past the window's
    // right edge, which is the screen's, so the tail of the slide is clipped
    // away rather than fading in mid-air.
    readonly property int slide: 72

    // Screenshots to the desktop and recordings to ~/Movies, which is where
    // macOS puts them; an explicit savePath in settings still wins.
    function saveDirFor(path: string): string {
        if (path.endsWith(".mov"))
            return Config.options.screenRecord.savePath !== "" ? Config.options.screenRecord.savePath : FileUtils.trimFileProtocol(Directories.videos);
        return Config.options.screenSnip.savePath !== "" ? Config.options.screenSnip.savePath : FileUtils.trimFileProtocol(Directories.desktop);
    }

    // Timed out, or clicked: keep it, in the directory its kind belongs in.
    // `then` is a command to run on the filed copy -- one shell line rather than
    // two detached ones, so the open cannot beat the move to the file.
    function keep(path, then = "") {
        const dir = StringUtils.shellSingleQuoteEscape(root.saveDirFor(path));
        const file = StringUtils.shellSingleQuoteEscape(path);
        const name = StringUtils.shellSingleQuoteEscape(path.split("/").pop());
        const open = then.length > 0 ? ` && ${then} '${dir}/${name}'` : "";
        Quickshell.execDetached(["bash", "-c", `mkdir -p '${dir}' && mv '${file}' '${dir}/'${open}`]);
    }

    // Dragged out: whoever took the drop owns it now.
    function discard(path: string): void {
        Quickshell.execDetached(["rm", "-f", path]);
    }

    // Not inside the window: the window's own visibility is derived from this,
    // so it cannot be the thing that owns it.
    FolderListModel {
        id: shelfModel

        folder: `file://${Directories.captureShelf}`
        nameFilters: ["*.png", "*.mov"]
        showDirs: false
        // Hidden names are captures still being written, and stay out of sight
        // until whoever is writing renames them into place.
        showHidden: false
        // Oldest first, so a new capture joins the bottom of the stack nearest
        // the corner rather than shoving the others down.
        sortField: FolderListModel.Time
        sortReversed: true
    }

    PanelWindow {
        id: win

        visible: shelfModel.count > 0 && !GlobalStates.screenLocked
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null

        WlrLayershell.namespace: "quickshell:captureShelf"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusiveZone: 0
        color: "transparent"

        anchors {
            right: true
            bottom: true
        }
        margins {
            // Sits above the dock rather than behind it. ponytail: the dock's
            // resting height, not whether it happens to be revealed right now --
            // hovering a thumbnail a dock's height above nothing is a smaller
            // problem than hiding it under a dock that is out.
            bottom: (Config.options?.dock.enable ?? false) ? (Config.options?.dock.height ?? 70) + Appearance.sizes.hyprlandGapsOut : 0
        }

        implicitWidth: root.cardWidth + root.slide + Appearance.sizes.elevationMargin * 2
        implicitHeight: cards.implicitHeight + Appearance.sizes.elevationMargin * 2

        // Only the cards take the mouse; the rest of the window is a hole.
        mask: Region {
            item: cards
        }

        Column {
            id: cards

            anchors {
                right: parent.right
                rightMargin: Appearance.sizes.elevationMargin + Appearance.sizes.hyprlandGapsOut
                bottom: parent.bottom
                bottomMargin: Appearance.sizes.elevationMargin
            }
            spacing: 10

            Repeater {
                model: shelfModel

                delegate: Item {
                    id: card

                    required property string filePath
                    required property string fileName

                    readonly property bool isVideo: card.fileName.endsWith(".mov")
                    readonly property string fileUri: `file://${encodeURI(card.filePath)}`
                    readonly property string thumbUri: `file://${encodeURI(Directories.captureShelfThumbs)}/${encodeURIComponent(card.fileName)}.png`
                    property bool posterDone: false

                    implicitWidth: root.cardWidth
                    implicitHeight: root.cardHeight

                    // Off the edge and invisible until the entry animation runs.
                    // Column positions its children vertically only, so x is ours
                    // to animate.
                    x: root.slide
                    opacity: 0
                    Component.onCompleted: entry.start()

                    // The drag is the same shape the file manager's is:
                    // text/uri-list is what macOS reads as a file drag, so the
                    // drop lands wherever a Finder drag would, and Automatic
                    // means a real platform drag rather than a QML-internal one.
                    Drag.dragType: Drag.Automatic
                    Drag.supportedActions: Qt.CopyAction
                    Drag.mimeData: ({
                            "text/uri-list": card.fileUri
                        })
                    Drag.imageSource: card.isVideo ? (card.posterDone ? card.thumbUri : "") : card.fileUri
                    // Anything that refuses the drop answers IgnoreAction, and the
                    // card is left alone to time out normally.
                    Drag.onDragFinished: dropAction => {
                        if (dropAction !== Qt.IgnoreAction)
                            root.discard(card.filePath);
                    }

                    ParallelAnimation {
                        id: entry

                        NumberAnimation {
                            target: card
                            property: "x"
                            to: 0
                            duration: Appearance.animation.elementMove.duration
                            easing.type: Appearance.animation.elementMove.type
                            easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                        }
                        NumberAnimation {
                            target: card
                            property: "opacity"
                            to: 1
                            duration: Appearance.animation.elementMoveFast.duration
                        }
                    }

                    SequentialAnimation {
                        id: exit

                        ParallelAnimation {
                            NumberAnimation {
                                target: card
                                property: "x"
                                to: root.slide
                                duration: Appearance.animation.elementMove.duration
                                easing.type: Easing.InCubic
                            }
                            NumberAnimation {
                                target: card
                                property: "opacity"
                                to: 0
                                duration: Appearance.animation.elementMove.duration
                            }
                        }
                        // Only once it is out of sight: moving the file is what
                        // destroys this delegate.
                        ScriptAction {
                            script: root.keep(card.filePath)
                        }
                    }

                    Timer {
                        // Held while the pointer is on the card or a drag is in
                        // flight, so the thing being reached for cannot vanish
                        // mid-reach. Leaving the card starts the wait over, which
                        // is the forgiving way round.
                        running: !mouseArea.containsMouse && !card.Drag.active
                        interval: root.lingerMs
                        onTriggered: exit.start()
                    }

                    // The first frame, for a recording. qlmanage is the same
                    // thumbnailer Finder uses, so a format QuickTime can play has
                    // a poster without this shell knowing anything about video.
                    Process {
                        running: card.isVideo
                        command: ["bash", "-c", `mkdir -p '${StringUtils.shellSingleQuoteEscape(Directories.captureShelfThumbs)}' && qlmanage -t -s 512 -o '${StringUtils.shellSingleQuoteEscape(Directories.captureShelfThumbs)}' '${StringUtils.shellSingleQuoteEscape(card.filePath)}'`]
                        // Whether it worked is the Image's problem: a poster that
                        // never arrived leaves the glyph showing.
                        onExited: card.posterDone = true
                    }

                    StyledRectangularShadow {
                        target: frame
                    }

                    Rectangle {
                        id: frame

                        anchors.fill: parent
                        radius: Appearance.rounding.small
                        color: Appearance.m3colors.m3surfaceContainerHigh
                        border.width: 1
                        border.color: Appearance.colors.colOutlineVariant
                        clip: true

                        Image {
                            id: preview

                            anchors.fill: parent
                            anchors.margins: 4
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            // A 5K screenshot decoded at 5K to be shown 232 wide
                            // for five seconds is a lot of memory for nothing.
                            sourceSize.width: root.cardWidth * 2
                            source: card.isVideo ? (card.posterDone ? card.thumbUri : "") : card.fileUri
                            visible: preview.status === Image.Ready
                        }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            visible: !preview.visible
                            text: card.isVideo ? "movie" : "image"
                            iconSize: 42
                            color: Appearance.colors.colOnLayer1
                        }
                    }

                    MouseArea {
                        id: mouseArea

                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton

                        property real pressX: 0
                        property real pressY: 0
                        property bool dragStarted: false

                        onPressed: mouse => {
                            mouseArea.pressX = mouse.x;
                            mouseArea.pressY = mouse.y;
                            mouseArea.dragStarted = false;
                        }
                        onPositionChanged: mouse => {
                            if (!mouseArea.pressed || mouseArea.dragStarted)
                                return;
                            if (Math.abs(mouse.x - mouseArea.pressX) < 6 && Math.abs(mouse.y - mouseArea.pressY) < 6)
                                return;
                            mouseArea.dragStarted = true;
                            // dragType Automatic turns this into a real platform
                            // drag as soon as the attached object goes active;
                            // startDrag() is for Drag.None and refuses to run
                            // before that.
                            card.Drag.active = true;
                        }
                        onReleased: {
                            card.Drag.active = false;
                            mouseArea.dragStarted = false;
                        }
                        // Clicking files the capture and opens it, the way
                        // clicking Apple's thumbnail does. Screenshots go to the
                        // shell's viewer; a recording has no viewer here, so it
                        // goes wherever macOS sends a .mov.
                        onClicked: {
                            if (mouseArea.dragStarted)
                                return;
                            root.keep(card.filePath, card.isVideo ? "open" : "qs-preview");
                        }
                    }
                }
            }
        }
    }
}
