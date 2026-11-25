import QtQuick
import Quickshell

import qs.modules.captureShelf
import qs.modules.common
import qs.modules.background
import qs.modules.bar
import qs.modules.cheatsheet
import qs.modules.dock
import qs.modules.lock
import qs.modules.mediaControls
import qs.modules.notificationPopup
import qs.modules.onScreenDisplay
import qs.modules.onScreenKeyboard
import qs.modules.overview
import qs.modules.regionSelector
import qs.modules.screenCorners
import qs.modules.screenRecord
import qs.modules.sessionScreen
import qs.modules.studyMode
import qs.modules.sidebarLeft
import qs.modules.sidebarRight
import qs.modules.overlay
import qs.modules.wallpaperSelector

// Fusion mode (services/FusionMode.qml) keeps only screenshots, the lock screen
// and the volume/brightness OSD -- the keys are grabbed by Karabiner, so
// without the OSD a volume press would give no feedback at all.
Scope {
    PanelLoader { component: Bar {} }
    PanelLoader { component: Background {} }
    PanelLoader { keepInFusion: true; component: CaptureShelf {} }
    PanelLoader { component: Cheatsheet {} }
    PanelLoader { extraCondition: Config.options.dock.enable; component: Dock {} }
    PanelLoader { keepInFusion: true; component: Lock {} }
    PanelLoader { component: MediaControls {} }
    PanelLoader { component: NotificationPopup {} }
    PanelLoader { keepInFusion: true; component: OnScreenDisplay {} }
    PanelLoader { component: OnScreenKeyboard {} }
    PanelLoader { component: Overlay {} }
    PanelLoader { component: Overview {} }
    PanelLoader { keepInFusion: true; component: RegionSelector {} }
    PanelLoader { component: ScreenCorners {} }
    PanelLoader { keepInFusion: true; component: ScreenRecordOverlay {} }
    PanelLoader { component: SessionScreen {} }
    PanelLoader { component: StudyModePanel {} }
    PanelLoader { component: SidebarLeft {} }
    PanelLoader { component: SidebarRight {} }
    PanelLoader { component: WallpaperSelector {} }
}
