import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root

    property Component regionComponent: Component {
        Region {}
    }
    
    Loader {
        id: overlayLoader
        // Built once and kept, rather than created and destroyed around every
        // open. Rebuilding meant a new native window and a fresh panel
        // registration each time, and the outgoing window outlived the incoming
        // one -- two full screen panels sat at the same level, with the stale
        // one's config applied last and winning, so the overlay came up looking
        // wrong or not at all. Keeping it costs memory and nothing else: Qt
        // Quick does not render a hidden window, and the widgets read singleton
        // services that poll for the bar whether the overlay is up or not.
        active: true
        sourceComponent: PanelWindow {
            id: overlayWindow
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:overlay"
            // Under application windows, above the desktop. The Cocoa backend maps
            // WlrLayer.Bottom to PanelLayer::Bottom, which is exactly that; Overlay
            // (the upstream value) sits above even full screen spaces.
            WlrLayershell.layer: WlrLayer.Bottom
            // Use OnDemand for pinned widgets to allow focus switching with mouse clicks
            WlrLayershell.keyboardFocus: GlobalStates.overlayOpen ? WlrKeyboardFocus.Exclusive : (OverlayContext.clickableWidgets.length > 0 ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None)
            visible: GlobalStates.overlayOpen || OverlayContext.hasPinnedWidgets
            color: "transparent"

            mask: Region {
                item: GlobalStates.overlayOpen ? overlayContent : null
                regions: OverlayContext.clickableWidgets.map((widget) => regionComponent.createObject(this, {
                    item: widget
                }));
            }

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            // No focus grab. Upstream dismisses the overlay when a click lands in
            // another application, which is the right behaviour for a panel that
            // sits on top of everything: the click was you reaching past it. Now
            // that it sits underneath, every click on any window is "outside" it,
            // so the grab would close the widgets the instant you touched
            // anything -- the opposite of a layer you leave up behind your work.
            // The keybind toggles it instead.

            OverlayContent {
                id: overlayContent
                anchors.fill: parent
            }
        }
    }

    IpcHandler {
        target: "overlay"

        function toggle(): void {
            GlobalStates.overlayOpen = !GlobalStates.overlayOpen;
        }
    }

    GlobalShortcut {
        name: "overlayToggle"
        description: "Toggles overlay on press"

        onPressed: {
            GlobalStates.overlayOpen = !GlobalStates.overlayOpen;
        }
    }
}
