import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas

Item {
    id: root
    focus: true
    readonly property bool usePasswordChars: !PolkitService.flow?.responseVisible ?? true

    Keys.onPressed: (event) => { // Esc to close
        if (event.key === Qt.Key_Escape) {
            GlobalStates.overlayOpen = false;
        }
    }

    property real initScale: Config.options.overlay.openingZoomAnimation ? 1.08 : 1.000001
    scale: initScale
    Component.onCompleted: {
        scale = 1
    }
    Behavior on scale {
        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
    }

    Rectangle {
        id: bg
        anchors.fill: parent
        color: Appearance.colors.colScrim
        visible: Config.options.overlay.darkenScreen && opacity > 0
        opacity: (GlobalStates.overlayOpen && root.scale !== initScale) ? 1 : 0
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }

    WidgetCanvas {
        id: canvas
        anchors.fill: parent

        // A click dismisses, a drag does not. If a widget's drag loses its grab
        // partway the release lands here instead of on the widget, and closing
        // on that is what made dragging a widget dismiss the whole overlay.
        // Dragging the backdrop is not a dismissal in its own right either.
        property point pressPoint
        onPressed: event => canvas.pressPoint = Qt.point(event.x, event.y)
        onClicked: event => {
            const moved = Math.abs(event.x - canvas.pressPoint.x)
                        + Math.abs(event.y - canvas.pressPoint.y);
            if (moved > 8) return;
            GlobalStates.overlayOpen = false;
        }

        OverlayTaskbar {
            anchors {
                horizontalCenter: parent.horizontalCenter
                top: parent.top
                topMargin: 50
            }
        }

        Repeater {
            model: ScriptModel {
                values: Persistent.states.overlay.open.map(identifier => {
                    return OverlayContext.availableWidgets.find(w => w.identifier === identifier);
                })
                objectProp: "identifier"
            }
            delegate: OverlayWidgetDelegateChooser {
                
            }
        }
    }
}
