pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

/**
 * The recording picker: the screen dimmed a little, with a toolbar near the
 * bottom in the shape macOS's own cmd+shift+5 toolbar takes.
 *
 * Replaces the dropdown that used to fall out of the bar button. A dropdown
 * hanging off the top of the screen cannot show what is about to be recorded;
 * dimming and moving the choice to the bottom leaves the desktop visible behind
 * it, which is the whole point of picking a window or a region.
 *
 * ponytail: one window on the primary screen, not one per screen. There is one
 * display here; a second would want the dim on both and the toolbar on the
 * focused one.
 */
Scope {
    id: root

    enum Mode {
        Screen,
        Window,
        Region
    }

    property int mode: ScreenRecordOverlay.Mode.Screen

    // Worth offering: mapped, not minimised, and big enough that screencapture
    // will not reject the rect.
    readonly property var recordableWindows: HyprlandData.windowList.filter(w => //
        !w.hidden && w.size[0] > 16 && w.size[1] > 16)

    // Kept by address rather than by index, so a window opening or closing while
    // the picker is up does not silently retarget the recording. Falls back to
    // the first window, so Record is never armed with nothing selected.
    property string selectedAddress: ""
    readonly property var selectedWindow: root.recordableWindows.find(w => w.address === root.selectedAddress) //
        ?? (root.recordableWindows[0] ?? null)

    function close(): void {
        GlobalStates.screenRecordOverlayOpen = false;
    }

    function start(): void {
        root.close();
        switch (root.mode) {
        case ScreenRecordOverlay.Mode.Screen:
            ScreenRecording.recordFullscreen();
            break;
        case ScreenRecordOverlay.Mode.Window:
            const win = root.selectedWindow;
            if (win)
                ScreenRecording.recordRegion(win.at[0], win.at[1], win.size[0], win.size[1]);
            break;
        case ScreenRecordOverlay.Mode.Region:
            // The region selector owns dragging and window snapping already, and
            // it lives in the panel family rather than here, so it is reached the
            // way the bar's snip button reaches it.
            Quickshell.execDetached(["qs", "-p", Quickshell.shellPath(""), "ipc", "call", "region", "record"]);
            break;
        }
    }

    LazyLoader {
        active: GlobalStates.screenRecordOverlayOpen

        component: PanelWindow {
            id: win

            color: "transparent"
            WlrLayershell.namespace: "quickshell:screenRecordOverlay"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            exclusionMode: ExclusionMode.Ignore
            anchors {
                left: true
                right: true
                top: true
                bottom: true
            }

            // The dim, and everywhere that is not the toolbar. Clicking out or
            // pressing Escape closes, so the picker is never a trap.
            Rectangle {
                anchors.fill: parent
                color: ColorUtils.transparentize("#000000", 0.75)

                focus: true
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape)
                        root.close();
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.close()
                }
            }

            // The list of windows to pick from, above the toolbar, only while
            // that is the mode being recorded.
            StyledRectangularShadow {
                target: windowCard
            }
            Rectangle {
                id: windowCard

                visible: root.mode === ScreenRecordOverlay.Mode.Window && root.recordableWindows.length > 0
                anchors {
                    horizontalCenter: parent.horizontalCenter
                    bottom: toolbar.top
                    bottomMargin: 10
                }
                implicitWidth: 320
                implicitHeight: windowColumn.implicitHeight + 8
                radius: Appearance.rounding.small
                color: Appearance.m3colors.m3surfaceContainer
                border.width: 1
                border.color: Appearance.colors.colLayer0Border

                // Swallow clicks that land on the card but not on a row, so they
                // do not reach the dismiss area underneath.
                MouseArea {
                    anchors.fill: parent
                }

                ColumnLayout {
                    id: windowColumn
                    anchors.fill: parent
                    anchors.margins: 4
                    spacing: 2

                    Repeater {
                        // ponytail: capped rather than scrollable — 14 rows still
                        // clear the top of the screen, and nobody picks the 15th
                        // window off an unsorted list anyway.
                        model: root.recordableWindows.slice(0, 14)

                        MenuButton {
                            required property var modelData

                            readonly property bool picked: root.selectedWindow?.address === modelData.address

                            Layout.fillWidth: true
                            // The container colour, not colLayer2Active: on a
                            // full-width row the layer tint is too faint to tell
                            // you what is about to be recorded.
                            colBackground: picked ? Appearance.colors.colSecondaryContainer : "transparent"
                            colBackgroundHover: picked ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer1Hover
                            buttonText: {
                                const label = modelData.title ? `${modelData.class} — ${modelData.title}` : modelData.class;
                                // ponytail: truncated rather than elided —
                                // MenuButton does not expose its text item to set
                                // elide on, and 36 characters fit the fixed width
                                // above with room to spare.
                                return label.length > 36 ? label.slice(0, 35) + "…" : label;
                            }
                            onClicked: root.selectedAddress = modelData.address
                        }
                    }
                }
            }

            StyledRectangularShadow {
                target: toolbar
            }
            Rectangle {
                id: toolbar

                anchors {
                    horizontalCenter: parent.horizontalCenter
                    bottom: parent.bottom
                    bottomMargin: 64
                }
                implicitWidth: toolbarRow.implicitWidth + 14
                implicitHeight: toolbarRow.implicitHeight + 14
                radius: Appearance.rounding.small
                color: Appearance.m3colors.m3surfaceContainer
                border.width: 1
                border.color: Appearance.colors.colLayer0Border

                MouseArea {
                    anchors.fill: parent
                }

                RowLayout {
                    id: toolbarRow
                    anchors.fill: parent
                    anchors.margins: 7
                    spacing: 4

                    ToolbarIconButton {
                        symbol: "close"
                        tooltipText: Translation.tr("Close")
                        onClicked: root.close()
                    }

                    Separator {}

                    ToolbarIconButton {
                        symbol: "screenshot_monitor"
                        tooltipText: Translation.tr("Record entire screen")
                        selected: root.mode === ScreenRecordOverlay.Mode.Screen
                        onClicked: root.mode = ScreenRecordOverlay.Mode.Screen
                    }

                    ToolbarIconButton {
                        symbol: "select_window"
                        tooltipText: Translation.tr("Record a window")
                        selected: root.mode === ScreenRecordOverlay.Mode.Window
                        onClicked: root.mode = ScreenRecordOverlay.Mode.Window
                    }

                    ToolbarIconButton {
                        symbol: "screenshot_region"
                        tooltipText: Translation.tr("Record a selected portion")
                        selected: root.mode === ScreenRecordOverlay.Mode.Region
                        onClicked: root.mode = ScreenRecordOverlay.Mode.Region
                    }

                    Separator {}

                    RippleButton {
                        implicitHeight: 36
                        implicitWidth: recordLabel.implicitWidth + 34
                        buttonRadius: Appearance.rounding.verysmall
                        colBackground: Appearance.colors.colPrimary
                        colBackgroundHover: Appearance.colors.colPrimaryHover
                        colRipple: Appearance.colors.colPrimaryActive
                        onClicked: root.start()

                        contentItem: StyledText {
                            id: recordLabel
                            anchors.centerIn: parent
                            text: Translation.tr("Record")
                            color: Appearance.colors.colOnPrimary
                        }
                    }
                }
            }
        }
    }

    component Separator: Rectangle {
        Layout.preferredWidth: 1
        Layout.preferredHeight: 22
        Layout.leftMargin: 2
        Layout.rightMargin: 2
        color: Appearance.m3colors.m3outlineVariant
    }

    component ToolbarIconButton: RippleButton {
        id: iconButton

        required property string symbol
        property string tooltipText: ""
        // Not `checked`: AbstractButton declares that one FINAL.
        property bool selected: false

        implicitWidth: 42
        implicitHeight: 36
        buttonRadius: Appearance.rounding.verysmall
        colBackground: selected ? Appearance.colors.colLayer2Active : ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1)
        colBackgroundHover: Appearance.colors.colLayer1Hover
        colRipple: Appearance.colors.colLayer1Active

        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: iconButton.symbol
            iconSize: 22
            fill: iconButton.selected ? 1 : 0
            color: Appearance.colors.colOnLayer1
        }

        StyledToolTip {
            text: iconButton.tooltipText
        }
    }
}
