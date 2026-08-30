pragma Singleton

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Wayland

Singleton {
    id: root

    // Compared case-insensitively because the two sides disagree: `apps` keys
    // every entry by a lower-cased id so a pinned app and its open windows
    // merge into one button, while pinnedApps holds the name as macOS spells it
    // -- "Firefox" pinned, "firefox" asked about. An exact match reported every
    // pinned app as unpinned, and pinning one appended a second entry.
    function isPinned(appId) {
        return Config.options.dock.pinnedApps.some(id => id.toLowerCase() === appId.toLowerCase());
    }

    function togglePin(appId) {
        if (root.isPinned(appId)) {
            Config.options.dock.pinnedApps = Config.options.dock.pinnedApps.filter(id => id.toLowerCase() !== appId.toLowerCase())
        } else {
            Config.options.dock.pinnedApps = Config.options.dock.pinnedApps.concat([appId])
        }
    }

    property list<var> apps: {
        var map = new Map();

        // Pinned apps
        const pinnedApps = Config.options?.dock.pinnedApps ?? [];
        for (const appId of pinnedApps) {
            if (!map.has(appId.toLowerCase())) map.set(appId.toLowerCase(), ({
                pinned: true,
                toplevels: []
            }));
        }

        // Separator
        if (pinnedApps.length > 0) {
            map.set("SEPARATOR", { pinned: false, toplevels: [] });
        }

        // Ignored apps
        const ignoredRegexStrings = Config.options?.dock.ignoredAppRegexes ?? [];
        const ignoredRegexes = ignoredRegexStrings.map(pattern => new RegExp(pattern, "i"));
        // Open windows
        for (const toplevel of ToplevelManager.toplevels.values) {
            // Files.app and Settings.app (qs-make-app) exec a copy of the
            // shared binary renamed to "quickshell-engine" inside their own
            // bundle, so yabai reports every one of their windows as app
            // "quickshell-engine" -- which is also a default ignoredAppRegexes
            // entry, so both windows vanished from the dock: their pins never
            // lit up, and hovering them never showed a preview, even while
            // the window was open and focused. The window title is the one
            // thing that still tells them apart (it is the mini-app's own
            // name, e.g. "Files"), so group by that instead whenever it is
            // populated. An untitled "quickshell-engine" toplevel is the
            // invisible root surface every quickshell process starts with,
            // not a real window, so it still falls through to ignoredRegexes.
            const isMiniApp = toplevel.appId.toLowerCase() === "quickshell-engine" && toplevel.title.length > 0;
            const appId = isMiniApp ? toplevel.title : toplevel.appId;
            if (!isMiniApp && ignoredRegexes.some(re => re.test(appId))) continue;
            if (!map.has(appId.toLowerCase())) map.set(appId.toLowerCase(), ({
                pinned: false,
                toplevels: []
            }));
            map.get(appId.toLowerCase()).toplevels.push(toplevel);
        }

        var values = [];

        for (const [key, value] of map) {
            values.push(appEntryComp.createObject(null, { appId: key, toplevels: value.toplevels, pinned: value.pinned }));
        }

        return values;
    }

    component TaskbarAppEntry: QtObject {
        id: wrapper
        required property string appId
        required property list<var> toplevels
        required property bool pinned
    }
    Component {
        id: appEntryComp
        TaskbarAppEntry {}
    }
}
