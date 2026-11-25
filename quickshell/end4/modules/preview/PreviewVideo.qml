import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import QtMultimedia

/**
 * Video for the preview window. Its own file, loaded on demand, so opening a
 * screenshot never pays for QtMultimedia. AVFoundation does the decoding, so
 * it plays whatever QuickTime plays.
 */
Item {
    id: root

    property string path: ""
    readonly property alias player: player

    function togglePlay(): void {
        if (player.playbackState === MediaPlayer.PlayingState)
            player.pause();
        else
            player.play();
    }

    function seekBy(ms: int): void {
        player.position = Math.max(0, Math.min(player.duration, player.position + ms));
    }

    function clock(ms: real): string {
        const s = Math.floor(ms / 1000);
        return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
    }

    MediaPlayer {
        id: player

        source: root.path.length > 0 ? `file://${encodeURI(root.path)}` : ""
        videoOutput: output
        audioOutput: AudioOutput {}
    }

    // Not onSourceChanged: with the path passed in at creation, that fires
    // before videoOutput is wired up and the picture never arrives.
    Component.onCompleted: player.play()

    VideoOutput {
        id: output

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: controls.top
        anchors.margins: 8

        TapHandler {
            onTapped: root.togglePlay()
        }
    }

    RowLayout {
        id: controls

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 8
        spacing: 8

        IconToolbarButton {
            implicitHeight: 36
            text: player.playbackState === MediaPlayer.PlayingState ? "pause" : "play_arrow"
            downAction: () => root.togglePlay()
        }

        StyledText {
            text: root.clock(player.position)
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }

        StyledSlider {
            Layout.fillWidth: true
            usePercentTooltip: false
            from: 0
            to: Math.max(1, player.duration)
            value: player.position
            onMoved: player.position = value
        }

        StyledText {
            text: root.clock(player.duration)
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
    }
}
