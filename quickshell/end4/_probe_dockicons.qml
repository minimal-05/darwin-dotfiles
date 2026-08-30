// Probe for the dock's icon resolution (modules/dock/DockAppButton.qml):
// AppSearch.lookup() finds a window's desktop entry, and AppSearch.iconExists()
// decides between that entry's icon and the "no icon" glyph.
//
//   bin/qs-test <this> -- dockicons resolves Files '==' true
//   bin/qs-test <this> -- dockicons resolves Settings '==' true
//   bin/qs-test <this> -- dockicons resolves org.kde.dolphin '==' false
//   bin/qs-test <this> -- dockicons entry org.kde.dolphin '==' '(none)'
//   bin/qs-test <this> -- dockicons guess Todoist '==' application-x-executable
//
// The dolphin pair is the regression: an appId that names nothing installed
// walks guessIcon's whole ladder to "application-x-executable", an XDG theme
// name NSWorkspace has never heard of, and the dock used to draw it as a broken
// picture. It must not resolve, so that the glyph is what gets drawn.
//
// The Todoist case is a second, sneakier version of the same failure:
// guessIcon's fuzzy fallback matches an appId against every icon's full
// bundle *path* (icons here are absolute paths, not short XDG theme names),
// and a long enough path is a coincidental subsequence match for almost
// anything -- "Todoist" against "/System/Applications/Utilities/Audio MIDI
// Setup.app" scored just high enough to be trusted before iconGuessThreshold
// existed. That guess is a real, existing icon, so it drew a confident but
// wrong picture instead of the "no icon" glyph. Todoist itself need not be
// installed for this to hold; only Audio MIDI Setup (or some app whose path
// scores as high) has to be.
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

        function guess(appId: string): string {
            return AppSearch.guessIcon(appId);
        }

        function resolves(appId: string): string {
            return String(AppSearch.iconExists(icon(appId)));
        }
    }
}
