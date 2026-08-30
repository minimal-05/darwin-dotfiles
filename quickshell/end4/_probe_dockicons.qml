// Probe for the dock's icon resolution (modules/dock/DockAppButton.qml):
// AppSearch.lookup() finds a window's desktop entry, and AppSearch.iconExists()
// decides between that entry's icon and the "no icon" glyph.
//
//   bin/qs-test <this> -- dockicons resolves Files '==' true
//   bin/qs-test <this> -- dockicons resolves Settings '==' true
//   bin/qs-test <this> -- dockicons resolves org.kde.dolphin '==' false
//   bin/qs-test <this> -- dockicons entry org.kde.dolphin '==' '(none)'
//
// The dolphin pair is the regression: an appId that names nothing installed
// walks guessIcon's whole ladder to "application-x-executable", an XDG theme
// name NSWorkspace has never heard of, and the dock used to draw it as a broken
// picture. It must not resolve, so that the glyph is what gets drawn.
//
// `entry` on an app that *is* installed is a manual query, not an assertion:
// DesktopEntries fills in asynchronously and a name can still be missing on the
// first call after "Configuration Loaded" (Firefox reliably is). Use --shell and
// ask a second time. The dock has the same race and answers it the same way, by
// re-running the lookup on DesktopEntries.onApplicationsChanged.

import Quickshell
import Quickshell.Io
import qs.services

ShellRoot {
    IpcHandler {
        target: "dockicons"

        function entry(appId: string): string {
            return AppSearch.lookup(appId)?.id ?? "(none)";
        }

        function icon(appId: string): string {
            return AppSearch.lookup(appId)?.icon ?? AppSearch.guessIcon(appId);
        }

        function resolves(appId: string): string {
            return String(AppSearch.iconExists(icon(appId)));
        }
    }
}
