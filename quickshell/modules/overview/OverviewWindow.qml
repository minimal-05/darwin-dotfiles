pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

Item { // Window
    id: root
    property var toplevel
    property var windowData
    property var monitorData
    property var scale
    property bool restrictToWorkspace: true
    property real widthRatio: {
        const widgetWidth = widgetMonitor.transform & 1 ? widgetMonitor.height : widgetMonitor.width;
        const monitorWidth = monitorData.transform & 1 ? monitorData.height : monitorData.width;
        return (widgetWidth * monitorData.scale) / (monitorWidth * widgetMonitor.scale);
    }
    property real heightRatio: {
        const widgetHeight = widgetMonitor.transform & 1 ? widgetMonitor.width : widgetMonitor.height;
        const monitorHeight = monitorData.transform & 1 ? monitorData.width : monitorData.height;
        return (widgetHeight * monitorData.scale) / (monitorHeight * widgetMonitor.scale);
    }
    property real initX: {
        return Math.max((windowData?.at[0] - (monitorData?.x ?? 0) - monitorData?.reserved[0]) * widthRatio * root.scale, 0) + xOffset;
    }

    property real initY: {
        return Math.max((windowData?.at[1] - (monitorData?.y ?? 0) - monitorData?.reserved[1]) * heightRatio * root.scale, 0) + yOffset;
    }
    property real xOffset: 0
    property real yOffset: 0
    property var widgetMonitor
    property int widgetMonitorId: widgetMonitor.id

    property var targetWindowWidth: windowData?.size[0] * scale * widthRatio
    property var targetWindowHeight: windowData?.size[1] * scale * heightRatio
    property bool hovered: false
    property bool pressed: false

    property bool centerIcons: Config.options.overview.centerIcons
    property real iconGapRatio: 0.06
    property real iconToWindowRatio: centerIcons ? 0.35 : 0.15
    property real xwaylandIndicatorToIconRatio: 0.35
    property real iconToWindowRatioCompact: 0.6
    // Badge size, used once a preview is behind the icon.
    property real iconToWindowRatioBadge: 0.22
    // yabai reports the real application name ("Firefox", "kitty", "Visual
    // Studio Code"), which is exactly what the Cocoa icon lookup resolves
    // against LaunchServices. AppSearch.guessIcon() only knows how to reshape
    // a name into a freedesktop icon-theme id, and macOS has no icon theme,
    // so running the name through it can only lose.
    property string iconPath: Quickshell.iconPath(windowData?.class ?? "", "application-x-executable")
    property bool compactMode: Appearance.font.pixelSize.smaller * 4 > targetWindowHeight || Appearance.font.pixelSize.smaller * 4 > targetWindowWidth

    property bool indicateXWayland: windowData?.xwayland ?? false

    // Dragging or resizing assigns x/y/width/height directly, which destroys
    // the bindings below and leaves the tile stranded at whatever the pointer
    // left it. Restoring them hands the geometry back to the window data, so
    // the next yabai poll animates the tile to what the window actually became.
    function resetGeometry(): void {
        root.x = Qt.binding(() => root.initX);
        root.y = Qt.binding(() => root.initY);
        root.width = Qt.binding(() => root.targetWindowWidth);
        root.height = Qt.binding(() => root.targetWindowHeight);
    }

    x: initX
    y: initY
    width: targetWindowWidth
    height: targetWindowHeight
    opacity: windowData.monitor == widgetMonitorId ? 1 : 0.4

    property real topLeftRadius
    property real topRightRadius
    property real bottomLeftRadius
    property real bottomRightRadius

    layer.enabled: true
    layer.effect: OpacityMask {
        maskSource: Rectangle {
            width: root.width
            height: root.height
            topLeftRadius: root.topLeftRadius
            topRightRadius: root.topRightRadius
            bottomRightRadius: root.bottomRightRadius
            bottomLeftRadius: root.bottomLeftRadius
        }
    }

    Behavior on x {
        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
    }
    Behavior on y {
        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
    }
    Behavior on width {
        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
    }
    Behavior on height {
        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
    }

    ScreencopyView {
        id: windowPreview
        anchors.fill: parent
        captureSource: GlobalStates.overviewOpen ? root.toplevel : null
        live: true

        // Color overlay for interactions
        Rectangle {
            anchors.fill: parent
            topLeftRadius: root.topLeftRadius
            topRightRadius: root.topRightRadius
            bottomRightRadius: root.bottomRightRadius
            bottomLeftRadius: root.bottomLeftRadius
            color: pressed ? ColorUtils.transparentize(Appearance.colors.colLayer2Active, 0.5) : 
                hovered ? ColorUtils.transparentize(Appearance.colors.colLayer2Hover, 0.7) : 
                ColorUtils.transparentize(Appearance.colors.colLayer2)
            border.color : ColorUtils.transparentize(Appearance.m3colors.m3outline, 0.88)
            border.width : 1
        }

        Rectangle { // Scrim, so the badge reads on a light preview
            id: iconBadge
            visible: windowIcon.badge
            anchors.fill: windowIcon
            anchors.margins: -windowIcon.badgePad
            radius: height / 2
            color: ColorUtils.transparentize(Appearance.colors.colLayer1, 0.2)
        }

        StyledImage {
            id: windowIcon
            // Shown for every window, not just as a fallback: a preview of a
            // window on another space can be a blank or near-identical
            // rectangle, and the icon is what makes it identifiable at a
            // glance. It shrinks to a corner badge once there is a frame
            // behind it.
            property bool badge: windowPreview.hasContent
            property real baseSize: Math.min(root.targetWindowWidth, root.targetWindowHeight)
            property real badgePad: iconSize * 0.16
            anchors {
                top: (!badge && !root.centerIcons) ? parent.top : undefined
                bottom: badge ? parent.bottom : undefined
                left: (badge || !root.centerIcons) ? parent.left : undefined
                centerIn: (!badge && root.centerIcons) ? parent : undefined
                margins: baseSize * root.iconGapRatio + (badge ? windowIcon.badgePad : 0)
            }
            property var iconSize: {
                if (badge)
                    return Math.max(14, Math.min(44, baseSize * root.iconToWindowRatioBadge));
                return baseSize * (root.compactMode ? root.iconToWindowRatioCompact : root.iconToWindowRatio);
            }
            mipmap: true
            Layout.alignment: Qt.AlignHCenter
            source: root.iconPath
            width: iconSize
            height: iconSize

            Behavior on width {
                animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
            }
            Behavior on height {
                animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
            }
        }
    }
}
