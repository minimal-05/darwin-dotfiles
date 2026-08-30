pragma Singleton

import QtQuick
import Quickshell

/**
 * Which platform the shell is running on.
 *
 * Used to hide settings that cannot do anything here rather than leaving them
 * visible and dead. Prefer this over SystemInfo.distroId: that is filled in
 * asynchronously by a Process, so a `visible:` binding on it starts false and
 * flips a frame later, visibly flashing the section on every page load.
 * Qt.platform.os resolves before first paint.
 */
Singleton {
    readonly property bool isMacOS: Qt.platform.os === "osx"
    readonly property bool isLinux: Qt.platform.os === "linux"
}
