pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.bar
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

/**
 * The right-click menu for a dock icon, shaped like the one macOS's own Dock
 * puts up: the app's own actions on top, then its windows, then the options
 * and Hide/Quit.
 *
 * An app's real dock menu comes from -applicationDockMenu:, which only the
 * Dock is allowed to ask for. The next best source is the app's File menu over
 * Accessibility, which is where the same commands live -- QuickTime's three
 * recordings, Safari's new windows, Finder's new folders. Reading it costs
 * ~150ms and works on an app that is not frontmost, so the menu can go up
 * empty and fill in.
 *
 * ponytail: "enabled File-menu items starting with New" is the whole heuristic
 * for the app section. It lands QuickTime, the browsers and Finder exactly, and
 * misses apps whose dock actions are not File > New -- Spotify's transport
 * controls, Music, Mail's "Get New Mail". Those need a per-app table; add one
 * when an app you actually use is missing, not before.
 */
PanelWindow {
    id: root

    // The TaskbarApps entry the menu was opened for, and the desktop entry the
    // button already looked up, so launching goes through the same path a
    // plain click does.
    property var appEntry: null
    property var launchEntry: null

    // Centre of the icon, in this window's coordinates. The dock spans the
    // screen, so its window coordinates are the screen's.
    property real anchorX: 0

    // Height of the dock's own window, so the card sits on top of it.
    property real dockHeight: 70

    // The app's File > New commands. Cleared on open and filled by the query.
    property var newItems: []

    // yabai reports the app name with its real capitalisation; TaskbarApps
    // lower-cases it for the key it merges pinned and running entries on, and
    // System Events will not find a process by the lower-cased name.
    readonly property string appName: root.appEntry?.toplevels?.[0]?.appId ?? root.appEntry?.appId ?? ""
    readonly property bool appRunning: (root.appEntry?.toplevels?.length ?? 0) > 0

    readonly property var entries: {
        const entry = root.appEntry;
        if (!entry)
            return [];

        const out = [];

        for (const item of root.newItems) {
            out.push({
                label: item,
                action: () => root.runScript(pressScript, [root.appName, item])
            });
        }
        if (out.length > 0)
            out.push({ sep: true });

        if (root.appRunning) {
            for (const window of entry.toplevels) {
                out.push({
                    label: window.title && window.title.length > 0 ? window.title : root.appName,
                    check: window.activated,
                    action: () => window.activate()
                });
            }
            out.push({ sep: true });
        }

        out.push({
            label: Translation.tr("Keep in Dock"),
            check: TaskbarApps.isPinned(entry.appId),
            action: () => TaskbarApps.togglePin(entry.appId)
        });
        out.push({
            label: Translation.tr("Show in Finder"),
            action: () => root.runScript(revealScript, [root.appName])
        });
        out.push({ sep: true });

        if (root.appRunning) {
            out.push({
                label: Translation.tr("Hide"),
                action: () => root.runScript(hideScript, [root.appName])
            });
            out.push({
                label: Translation.tr("Quit"),
                action: () => root.runScript(quitScript, [root.appName])
            });
        } else {
            out.push({
                label: Translation.tr("Open"),
                action: () => root.launchEntry?.execute()
            });
        }

        return out;
    }

    function openFor(entry, launchEntry, centerX, dockHeight): void {
        root.appEntry = entry;
        root.launchEntry = launchEntry;
        root.anchorX = centerX;
        root.dockHeight = dockHeight;
        root.newItems = [];
        root.visible = true;

        newItemsQuery.running = false;
        newItemsQuery.command = ["osascript", "-e", newItemsScript, root.appName];
        newItemsQuery.running = true;
    }

    function dismiss(): void {
        root.visible = false;
        root.appEntry = null;
        root.newItems = [];
    }

    function runScript(script: string, args: var): void {
        Quickshell.execDetached(["osascript", "-e", script].concat(args));
    }

    visible: false

    // Full screen, so a click anywhere else closes the menu the way it does on
    // macOS. The scrim has to be drawn, not merely present: the Cocoa backend
    // hit-tests a non-opaque window against its rendered alpha, and a fully
    // transparent one lets the click through to whatever is underneath. One
    // step off zero is enough to catch it and invisible on any background.
    color: "#03000000"

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    WlrLayershell.namespace: "quickshell:popup"
    WlrLayershell.layer: WlrLayer.Overlay

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onPressed: root.dismiss()
    }

    StyledRectangularShadow {
        target: card
    }

    Rectangle {
        id: card

        readonly property real padding: 4
        readonly property real gap: Appearance.sizes.elevationMargin

        implicitWidth: Math.max(menuColumn.implicitWidth + padding * 2, 200)
        implicitHeight: menuColumn.implicitHeight + padding * 2
        width: implicitWidth
        height: implicitHeight

        x: Math.max(gap, Math.min(root.anchorX - width / 2, root.width - width - gap))
        y: root.height - root.dockHeight - height

        radius: Appearance.rounding.small
        color: Appearance.m3colors.m3surfaceContainer
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        // Swallow clicks that land on the card but not on a row, so they do not
        // reach the scrim and close the menu.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
        }

        ColumnLayout {
            id: menuColumn

            anchors.centerIn: parent
            width: parent.width - card.padding * 2
            spacing: 0

            Repeater {
                model: root.entries

                AppMenuRow {
                    required property var modelData

                    Layout.fillWidth: true
                    Layout.topMargin: modelData.sep ? 4 : 0
                    Layout.bottomMargin: modelData.sep ? 4 : 0

                    implicitHeight: modelData.sep ? 1 : 32
                    pointingHandCursor: !modelData.sep
                    rippleEnabled: !modelData.sep

                    // A separator is a row that is one pixel tall and does not
                    // light up, rather than a second delegate to switch between.
                    colBackground: modelData.sep ? Appearance.m3colors.m3outlineVariant : ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1)
                    colBackgroundHover: modelData.sep ? Appearance.m3colors.m3outlineVariant : Appearance.colors.colLayer1Hover

                    label: modelData.label ?? ""
                    trailing: modelData.check ? "✓" : ""

                    releaseAction: () => {
                        if (modelData.sep)
                            return;
                        modelData.action();
                        root.dismiss();
                    }
                }
            }
        }
    }

    Process {
        id: newItemsQuery

        stdout: StdioCollector {
            onStreamFinished: {
                root.newItems = text.split("\n").map(line => line.trim()).filter(line => line.length > 0).slice(0, 6);
            }
        }
    }

    readonly property string newItemsScript: `on run argv
	set out to ""
	try
		tell application "System Events" to tell process (item 1 of argv)
			repeat with mi in menu items of menu 1 of menu bar item "File" of menu bar 1
				set t to name of mi
				if t is not missing value and t starts with "New " then
					if enabled of mi and not (exists menu 1 of mi) then set out to out & t & linefeed
				end if
			end repeat
		end tell
	end try
	return out
end run`

    // Bring the app forward first, the way picking a real dock menu item does:
    // a recording window or a new document that opens behind everything reads
    // as nothing having happened.
    readonly property string pressScript: `on run argv
	tell application "System Events" to tell process (item 1 of argv)
		set frontmost to true
		click menu item (item 2 of argv) of menu 1 of menu bar item "File" of menu bar 1
	end tell
end run`

    // The bundle comes from the running process, never from the name: telling
    // an application by name to quit asks LaunchServices to resolve it, which
    // can start a different app that happens to match.
    readonly property string quitScript: `on run argv
	tell application "System Events" to set bid to bundle identifier of (first process whose name is (item 1 of argv))
	tell application id bid to quit
end run`

    readonly property string hideScript: `on run argv
	tell application "System Events" to set visible of (first process whose name is (item 1 of argv)) to false
end run`

    // A running app is revealed from its process, so the bundle actually in use
    // is the one shown; a pinned app that is not running falls back to the name.
    readonly property string revealScript: `on run argv
	try
		tell application "System Events" to set f to file of (first process whose name is (item 1 of argv))
	on error
		try
			set f to path to application (item 1 of argv)
		on error
			return
		end try
	end try
	tell application "Finder"
		reveal f
		activate
	end tell
end run`
}
