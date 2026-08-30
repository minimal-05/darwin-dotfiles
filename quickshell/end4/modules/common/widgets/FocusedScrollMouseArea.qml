import QtQuick

MouseArea { // Right side | scroll to change volume
    id: root

    signal scrollUp(delta: int)
    signal scrollDown(delta: int)
    signal movedAway()

    property bool hovered: false
    property real lastScrollX: 0
    property real lastScrollY: 0
    property bool trackingScroll: false
    property real moveThreshold: 20
    // ponytail: 0 = fire on every wheel event (old behavior). Trackpads send tiny
    // continuous deltas, so consumers that step a real value set this to a few
    // notches' worth (one mouse notch = 120) and get one step per accumulated notch.
    property real scrollStep: 0
    property real scrollAccumulated: 0

    acceptedButtons: Qt.LeftButton
    hoverEnabled: true

    onEntered: {
        root.hovered = true;
    }

    onExited: {
        root.hovered = false;
        root.trackingScroll = false;
        root.scrollAccumulated = 0;
    }

    onWheel: event => {
        root.scrollAccumulated += event.angleDelta.y;
        if (Math.abs(root.scrollAccumulated) >= root.scrollStep) {
            const delta = root.scrollAccumulated;
            root.scrollAccumulated = 0;
            if (delta < 0)
                root.scrollDown(delta);
            else if (delta > 0)
                root.scrollUp(delta);
        }
        // Store the mouse position and start tracking
        root.lastScrollX = event.x;
        root.lastScrollY = event.y;
        root.trackingScroll = true;
    }

    onPositionChanged: mouse => {
        if (root.trackingScroll) {
            const dx = mouse.x - root.lastScrollX;
            const dy = mouse.y - root.lastScrollY;
            if (Math.sqrt(dx * dx + dy * dy) > root.moveThreshold) {
                root.movedAway();
                root.trackingScroll = false;
            }
        }
    }

    onContainsMouseChanged: {
        if (!root.containsMouse && root.trackingScroll) {
            root.movedAway();
            root.trackingScroll = false;
        }
    }
}
