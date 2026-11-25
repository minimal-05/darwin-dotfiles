import qs.modules.common
import QtQuick
import QtQuick.Window
import Quickshell

/**
 * One file manager window. The app owns a list of these -- see finder.qml --
 * rather than a single window, so Cmd+N and a second launch get their own.
 *
 * Window, not ApplicationWindow: ApplicationWindow insets its content by the
 * titlebar height (28pt) as a safe area, and this fork already strips the
 * titlebar for panel-less processes -- so that inset was 28pt of dead space at
 * the top of every window with nothing above it.
 */
Window {
    id: win

    // Empty for a plain window; "dark" or "light" while this window is standing
    // in for the system's wallpaper open panel.
    property alias pickMode: content.pickMode

    // Offset for each further window, so a new one does not land exactly on top
    // of the last.
    property int cascade: 0

    // Closing is the owner's call: the last window hides to keep the process
    // warm, any other one is destroyed.
    signal closeRequested
    signal newWindowRequested
    signal picked(string path, string mode)

    // The title is the handle yabai has on this window: the picker is matched by
    // it and left unmanaged, so it floats over whatever asked for it rather than
    // being tiled into the layout. See the rule in src/tools/qs-finder.
    title: win.pickMode.length > 0 ? "Choose a wallpaper" : "Files"

    minimumWidth: 360
    minimumHeight: 280
    width: 1000
    height: 640
    color: Appearance.m3colors.m3background

    x: Screen.width / 2 - win.width / 2 + win.cascade * 28
    y: Screen.height / 2 - win.height / 2 + win.cascade * 28

    // A defensive backstop for any native close request that is not one of
    // the two Shortcuts above (which call closeRequested() directly and never
    // reach this at all): only the window that actually has focus turns it
    // into a real close, so nothing here can cascade into closing every
    // window at once the way Cmd+Q's own native handling used to.
    onClosing: close => {
        close.accepted = false;
        if (win.active)
            win.closeRequested();
    }

    // Hiding is a cancel: a pick left armed would greet the next plain open with
    // the banner and swallow a double-click.
    onVisibleChanged: if (!win.visible) content.pickMode = "";

    function present(): void {
        win.visible = true;
        win.raise();
        win.requestActivate();
    }

    function navigate(path: string): void {
        content.navigate(path);
    }

    Shortcut {
        sequences: [StandardKey.New]
        onActivated: win.newWindowRequested()
    }

    // The fork strips the titlebar, so there are no traffic lights to close a
    // window with -- this is the only way out of one.
    Shortcut {
        sequences: [StandardKey.Close]
        onActivated: win.closeRequested()
    }

    // Cmd+Q's own native handling asks every top-level window to close at
    // once, not just the one in front (see src/cocoa/init.cpp, which strips
    // its key equivalent from the app menu for a config like this one with
    // more than one window). With that claim gone, the key press reaches here
    // instead, and behaves exactly like Cmd+W -- close what has focus, leave
    // the rest alone.
    Shortcut {
        sequences: [StandardKey.Quit]
        onActivated: win.closeRequested()
    }

    FinderContent {
        id: content

        anchors.fill: parent

        onPicked: path => win.picked(path, content.pickMode)
    }
}
