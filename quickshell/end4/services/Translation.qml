pragma Singleton

import QtQuick
import Quickshell

// The shell is English only here. tr() stays so the call sites need no change.
Singleton {
    function tr(text) {
        return text ? text.toString() : "";
    }
}
