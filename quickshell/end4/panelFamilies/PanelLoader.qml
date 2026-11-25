import QtQuick
import Quickshell

import qs
import qs.modules.common

LazyLoader {
    property bool extraCondition: true
    // Stays loaded while Fusion mode has hidden the rest of the shell.
    property bool keepInFusion: false
    active: Config.ready && extraCondition && (keepInFusion || !GlobalStates.fusionMode)
}
