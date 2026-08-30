import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import Qt.labs.synchronizer
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: overviewScope
    property bool dontAutoCancelSearch: false
    // ponytail: one open flag, two layouts. searchMode = launcher only (Cmd+Space),
    // else the workspace grid only (Super tap).
    property bool searchMode: false

    function setMode(search) {
        if (!search)
            searchWidget.cancelSearch();
        overviewScope.searchMode = search;
    }

    // No batch capture on open. Every tile's ScreencopyView already grabs its
    // own window the moment it becomes visible, so running qs-window-thumbs
    // over the whole window list captured all of them a second time -- and
    // serially, one screencapture after another, while the tiles were doing
    // theirs in parallel. Measured at 1.5s for seven windows, which is exactly
    // how long the grid took to stop rearranging itself: the icons sit large
    // and centred until a frame lands, then shrink to corner badges.
    //
    // ponytail: that batch was also the only thing pruning thumbnails of
    // windows that no longer exist. They are small and live in XDG_RUNTIME_DIR,
    // so they go at reboot; give the script a --prune mode and call it on close
    // if that ever actually costs anything.

    function toggleMode(search) {
        // Already open in the other mode: switch instead of closing.
        if (GlobalStates.overviewOpen && overviewScope.searchMode !== search) {
            overviewScope.setMode(search);
            return;
        }
        overviewScope.setMode(search);
        GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
    }

    PanelWindow {
        id: panelWindow
        property string searchingText: ""
        readonly property HyprlandMonitor monitor: Hyprland.monitorFor(panelWindow.screen)
        property bool monitorIsFocused: (Hyprland.focusedMonitor?.id == monitor?.id)
        visible: GlobalStates.overviewOpen

        WlrLayershell.namespace: "quickshell:overview"
        WlrLayershell.layer: WlrLayer.Top
        // Constant, like the mask below: dropping it on close makes the backend
        // reapply a plain borderless style and the panel stops being able to
        // take keys on later opens.
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        color: "transparent"

        // The mask keeps clicks outside the overview passing through to the app
        // underneath. It must NOT drop to null on close: the backend never
        // restores the input region afterwards, so every open after the first
        // could not take keyboard focus and the search field ate nothing.
        mask: Region {
            item: columnLayout
        }

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        Connections {
            target: GlobalStates
            function onOverviewOpenChanged() {
                if (!GlobalStates.overviewOpen) {
                    searchWidget.disableExpandAnimation();
                    overviewScope.dontAutoCancelSearch = false;
                    GlobalFocusGrab.dismiss();
                } else {
                    if (!overviewScope.dontAutoCancelSearch) {
                        searchWidget.cancelSearch();
                    }
                    GlobalFocusGrab.addDismissable(panelWindow);

                    // Ask yabai now rather than opening on the last poll. The
                    // shim polls windows once a second, so the grid was drawing
                    // tiles at whatever geometry was current up to a second ago
                    // and then animating them to the real sizes when the poll
                    // landed -- the whole grid visibly resizing itself after it
                    // was already up. One query is ~15ms.
                    HyprlandData.updateWindowList();
                }
            }
        }

        Connections {
            target: GlobalFocusGrab
            function onDismissed() {
                GlobalStates.overviewOpen = false;
            }
        }
        implicitWidth: columnLayout.implicitWidth
        implicitHeight: columnLayout.implicitHeight

        function setSearchingText(text) {
            searchWidget.setSearchingText(text);
            searchWidget.focusFirstItem();
        }

        Column {
            id: columnLayout
            visible: GlobalStates.overviewOpen
            anchors {
                horizontalCenter: parent.horizontalCenter
                top: parent.top
            }
            spacing: -8

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    GlobalStates.overviewOpen = false;
                }
            }

            SearchWidget {
                id: searchWidget
                visible: overviewScope.searchMode
                anchors.horizontalCenter: parent.horizontalCenter
                Synchronizer on searchingText {
                    property alias source: panelWindow.searchingText
                }
            }

            Loader {
                id: overviewLoader
                anchors.horizontalCenter: parent.horizontalCenter
                active: GlobalStates.overviewOpen && !overviewScope.searchMode && (Config?.options.overview.enable ?? true)
                focus: !overviewScope.searchMode
                sourceComponent: OverviewWidget {
                    screen: panelWindow.screen
                }
            }
        }
    }

    function toggleClipboard() {
        if (GlobalStates.overviewOpen && overviewScope.dontAutoCancelSearch) {
            GlobalStates.overviewOpen = false;
            return;
        }
        overviewScope.dontAutoCancelSearch = true;
        overviewScope.setMode(true);
        panelWindow.setSearchingText(Config.options.search.prefix.clipboard);
        GlobalStates.overviewOpen = true;
    }

    function toggleEmojis() {
        if (GlobalStates.overviewOpen && overviewScope.dontAutoCancelSearch) {
            GlobalStates.overviewOpen = false;
            return;
        }
        overviewScope.dontAutoCancelSearch = true;
        overviewScope.setMode(true);
        panelWindow.setSearchingText(Config.options.search.prefix.emojis);
        GlobalStates.overviewOpen = true;
    }

    IpcHandler {
        target: "search"

        function toggle() {
            overviewScope.toggleMode(true);
        }
        function workspacesToggle() {
            overviewScope.toggleMode(false);
        }
        function close() {
            GlobalStates.overviewOpen = false;
        }
        function open() {
            overviewScope.setMode(true);
            GlobalStates.overviewOpen = true;
        }
        function toggleReleaseInterrupt() {
            GlobalStates.superReleaseMightTrigger = false;
        }
        function clipboardToggle() {
            overviewScope.toggleClipboard();
        }
    }

    GlobalShortcut {
        name: "searchToggle"
        description: "Toggles search on press"

        onPressed: {
            overviewScope.toggleMode(true);
        }
    }
    GlobalShortcut {
        name: "overviewWorkspacesClose"
        description: "Closes overview on press"

        onPressed: {
            GlobalStates.overviewOpen = false;
        }
    }
    GlobalShortcut {
        name: "overviewWorkspacesToggle"
        description: "Toggles overview on press"

        onPressed: {
            overviewScope.toggleMode(false);
        }
    }
    GlobalShortcut {
        name: "searchToggleRelease"
        description: "Toggles search on release"

        onPressed: {
            GlobalStates.superReleaseMightTrigger = true;
        }

        onReleased: {
            if (!GlobalStates.superReleaseMightTrigger) {
                GlobalStates.superReleaseMightTrigger = true;
                return;
            }
            overviewScope.toggleMode(false);
        }
    }
    GlobalShortcut {
        name: "searchToggleReleaseInterrupt"
        description: "Interrupts possibility of search being toggled on release. " + "This is necessary because GlobalShortcut.onReleased in quickshell triggers whether or not you press something else while holding the key. " + "To make sure this works consistently, use binditn = MODKEYS, catchall in an automatically triggered submap that includes everything."

        onPressed: {
            GlobalStates.superReleaseMightTrigger = false;
        }
    }
    GlobalShortcut {
        name: "overviewClipboardToggle"
        description: "Toggle clipboard query on overview widget"

        onPressed: {
            overviewScope.toggleClipboard();
        }
    }

    GlobalShortcut {
        name: "overviewEmojiToggle"
        description: "Toggle emoji query on overview widget"

        onPressed: {
            overviewScope.toggleEmojis();
        }
    }
}
