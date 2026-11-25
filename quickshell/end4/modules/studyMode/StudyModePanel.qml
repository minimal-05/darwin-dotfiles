import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

/**
 * Everything study mode puts on screen besides the bar button: the confirmation
 * in front of a session, the focus warning, and the rewards tracker.
 *
 * Study mode is a one-way door for its duration -- that is the whole point of
 * it -- so the dialog says plainly what is about to happen and how to get out,
 * rather than asking "are you sure?" and leaving you to find out.
 */
Scope {
    id: root

    IpcHandler {
        target: "studyMode"

        // Opens the confirmation, never a session: starting still takes a
        // deliberate click.
        function confirm(): void {
            if (!StudyMode.active && !StudyMode.busy)
                GlobalStates.studyModeConfirmOpen = true;
        }

        function cancel(): void {
            GlobalStates.studyModeConfirmOpen = false;
        }

        function tracker(): void {
            GlobalStates.studyTrackerOpen = !GlobalStates.studyTrackerOpen;
        }
    }

    // Solid, not colLayer0: that one is translucent, and the blurred window
    // behind showed through the text.
    component Card: Rectangle {
        radius: Appearance.rounding.windowRounding
        color: Appearance.colors.colLayer0Base
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant
    }

    component Line: RowLayout {
        property alias icon: glyph.text
        property alias text: label.text
        Layout.fillWidth: true
        spacing: 10
        MaterialSymbol {
            id: glyph
            Layout.alignment: Qt.AlignTop
            iconSize: Appearance.font.pixelSize.large
            color: Appearance.colors.colPrimary
        }
        StyledText {
            id: label
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.normal
            color: Appearance.colors.colOnLayer0
        }
    }

    component Tile: Rectangle {
        id: tile
        property string value
        property string label
        Layout.fillWidth: true
        Layout.preferredWidth: 1 // equal thirds
        implicitHeight: tileText.implicitHeight + 16
        radius: Appearance.rounding.small
        color: Appearance.colors.colLayer1
        ColumnLayout {
            id: tileText
            anchors.centerIn: parent
            spacing: 0
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: tile.value
                font.pixelSize: Appearance.font.pixelSize.huge
                color: Appearance.colors.colOnLayer0
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: tile.label
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnLayer1
            }
        }
    }

    component PillButton: RippleButton {
        id: pill
        property color colText: Appearance.colors.colOnLayer0
        implicitHeight: 36
        leftPadding: 18
        rightPadding: 18
        buttonRadius: 18
        // The default label is colOnLayer, which was near-white on the peach
        // primary of the Start button.
        contentItem: StyledText {
            text: pill.buttonText
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.pixelSize: Appearance.font.pixelSize.normal
            color: pill.colText
        }
    }

    // --- Confirmation -------------------------------------------------------
    Loader {
        active: GlobalStates.studyModeConfirmOpen

        sourceComponent: PanelWindow {
            visible: true
            color: "transparent"

            WlrLayershell.namespace: "quickshell:studyModeConfirm"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            // Modal: the scrim takes the whole screen, and clicking it or
            // pressing Esc cancels -- the way out of a dialog should not be a
            // hunt for the Cancel button.
            Rectangle {
                anchors.fill: parent
                color: "#000000"
                opacity: 0.45
                MouseArea {
                    anchors.fill: parent
                    onClicked: GlobalStates.studyModeConfirmOpen = false
                }
            }

            Item {
                focus: true
                Keys.onEscapePressed: GlobalStates.studyModeConfirmOpen = false
                Keys.onReturnPressed: startButton.clicked()
            }

            Card {
                id: card
                anchors.centerIn: parent
                implicitWidth: 420
                implicitHeight: column.implicitHeight + 48

                MouseArea {
                    anchors.fill: parent
                }

                ColumnLayout {
                    id: column
                    anchors.centerIn: parent
                    width: parent.width - 48
                    spacing: 10

                    StyledText {
                        Layout.fillWidth: true
                        Layout.bottomMargin: 4
                        text: Translation.tr("Study for %1 minutes?").arg(Config.options.studyMode.durationMinutes)
                        font.pixelSize: Appearance.font.pixelSize.huge
                        color: Appearance.colors.colOnLayer0
                    }

                    Line {
                        icon: "visibility_off"
                        text: Translation.tr("Other apps are hidden, not closed. They come back when the timer ends.")
                    }
                    Line {
                        icon: "public"
                        text: Translation.tr("Firefox restarts with your tabs, and only your school sites will load.")
                    }
                    Line {
                        icon: "stars"
                        text: Translation.tr("Every focused minute earns a point. A warning plays if you drift or go idle.")
                    }

                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: Translation.tr("End early from Settings › General.")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer1
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        spacing: 8

                        Item {
                            Layout.fillWidth: true
                        }

                        PillButton {
                            buttonText: Translation.tr("Cancel")
                            onClicked: GlobalStates.studyModeConfirmOpen = false
                        }

                        PillButton {
                            id: startButton
                            buttonText: Translation.tr("Start")
                            colText: Appearance.colors.colOnPrimary
                            colBackground: Appearance.colors.colPrimary
                            colBackgroundHover: Appearance.colors.colPrimaryHover
                            colRipple: Appearance.colors.colPrimaryActive
                            onClicked: {
                                GlobalStates.studyModeConfirmOpen = false;
                                StudyMode.start(Config.options.studyMode.durationMinutes);
                            }
                        }
                    }
                }
            }

        }
    }

    // --- Focus warning ------------------------------------------------------
    // The script writes a warning at most once a minute; show each one once,
    // for a few seconds, while it is still fresh.
    property int shownWarnAt: 0
    property bool warnVisible: false

    property string bannerText: ""
    property string bannerIcon: "warning"

    function showBanner(icon, text): void {
        root.bannerIcon = icon;
        root.bannerText = text;
        root.warnVisible = true;
        warnTimer.restart();
    }

    Connections {
        target: StudyMode
        function onWarnChanged(): void {
            const at = StudyMode.warn?.at ?? 0;
            if (at > root.shownWarnAt && Date.now() / 1000 - at < 60) {
                root.shownWarnAt = at;
                root.showBanner("warning", StudyMode.warn.text);
            }
        }
        // start/stop failures used to vanish into the script's stderr: the
        // button did nothing and there was no telling why.
        function onErrorChanged(): void {
            if (StudyMode.error)
                root.showBanner("error", StudyMode.error.text);
        }
    }

    Timer {
        id: warnTimer
        interval: 8000
        onTriggered: root.warnVisible = false
    }

    Loader {
        active: root.warnVisible

        sourceComponent: PanelWindow {
            visible: true
            color: "transparent"
            exclusiveZone: 0
            implicitWidth: banner.implicitWidth
            implicitHeight: banner.implicitHeight

            WlrLayershell.namespace: "quickshell:studyWarning"
            WlrLayershell.layer: WlrLayer.Overlay

            anchors.top: true
            margins.top: Appearance.sizes.baseBarHeight + 8

            Rectangle {
                id: banner
                implicitWidth: bannerRow.implicitWidth + 32
                implicitHeight: bannerRow.implicitHeight + 20
                radius: height / 2
                color: Appearance.colors.colErrorContainer

                RowLayout {
                    id: bannerRow
                    anchors.centerIn: parent
                    spacing: 10
                    MaterialSymbol {
                        text: root.bannerIcon
                        iconSize: Appearance.font.pixelSize.huge
                        color: Appearance.colors.colOnErrorContainer
                    }
                    StyledText {
                        text: root.bannerText
                        font.pixelSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnErrorContainer
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.warnVisible = false
                }
            }
        }
    }

    // --- Celebrations ------------------------------------------------------
    // One at a time, queued: finishing a session can level you up and unlock
    // two badges on the same poll, and each deserves its own moment.
    property var celebrations: []
    property var current: null
    property int confettiBurst: 0

    function celebrate(c): void {
        root.celebrations = root.celebrations.concat([c]);
        if (!root.current)
            root.nextCelebration();
    }

    function nextCelebration(): void {
        if (root.celebrations.length === 0) {
            root.current = null;
            return;
        }
        root.current = root.celebrations[0];
        root.celebrations = root.celebrations.slice(1);
        if (root.current.confetti)
            root.confettiBurst++;
        Quickshell.execDetached(["afplay", root.current.sound]);
        celebrationTimer.restart();
    }

    Timer {
        id: celebrationTimer
        interval: 3800
        onTriggered: root.nextCelebration()
    }

    Connections {
        target: StudyMode
        function onSessionDone(): void {
            root.celebrate({ icon: "flag", title: Translation.tr("Session complete!"), subtitle: Translation.tr("+25 XP bonus · %1 sessions").arg(StudyMode.sessions), confetti: true, sound: "/System/Library/Sounds/Hero.aiff" });
        }
        function onLevelUp(level, title): void {
            root.celebrate({ icon: "keyboard_double_arrow_up", title: Translation.tr("Level %1!").arg(level), subtitle: Translation.tr("You're now a %1").arg(title), confetti: true, sound: "/System/Library/Sounds/Glass.aiff" });
        }
        function onUnlocked(badge): void {
            root.celebrate({ icon: badge.icon, title: Translation.tr("Badge unlocked: %1").arg(badge.name), subtitle: badge.desc, confetti: false, sound: "/System/Library/Sounds/Purr.aiff" });
        }
    }

    IpcHandler {
        target: "studyFx"
        // For trying the effects without earning them.
        function demo(): void {
            StudyMode.levelUp(StudyMode.level + 1, StudyMode.titles[Math.min(StudyMode.level, 9)]);
            StudyMode.unlocked(StudyMode.badges[7]);
        }
    }

    Loader {
        active: root.current !== null

        sourceComponent: PanelWindow {
            visible: true
            color: "transparent"
            exclusiveZone: 0
            WlrLayershell.namespace: "quickshell:studyCelebration"
            WlrLayershell.layer: WlrLayer.Overlay
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            // Click-through: a celebration never blocks work.
            mask: Region {}

            Loader {
                id: confetti
                anchors.fill: parent
                active: false
                Connections {
                    target: root
                    function onConfettiBurstChanged(): void {
                        confetti.active = false;
                        confetti.active = true;
                    }
                }
                Component.onCompleted: active = root.current?.confetti ?? false
                sourceComponent: Item {
                    Repeater {
                        model: 90
                        delegate: Rectangle {
                            id: bit
                            required property int index
                            readonly property var palette: [Appearance.colors.colPrimary, Appearance.colors.colTertiary ?? "#ffb4a8", Appearance.colors.colSecondary ?? "#e7bdb6", "#ffd54f", "#81c784", "#64b5f6", "#f06292"]
                            x: parent.width * Math.random()
                            y: -20
                            width: 6 + Math.random() * 8
                            height: width * (0.4 + Math.random() * 0.6)
                            radius: index % 3 === 0 ? width / 2 : 1
                            color: palette[index % palette.length]
                            ParallelAnimation {
                                running: true
                                NumberAnimation { target: bit; property: "y"; to: bit.parent.height * (0.5 + Math.random() * 0.5); duration: 1800 + Math.random() * 1600; easing.type: Easing.OutQuad }
                                NumberAnimation { target: bit; property: "x"; to: bit.x + (Math.random() - 0.5) * 300; duration: 3000 }
                                NumberAnimation { target: bit; property: "rotation"; to: (Math.random() - 0.5) * 1080; duration: 3000 }
                                SequentialAnimation {
                                    PauseAnimation { duration: 2200 }
                                    NumberAnimation { target: bit; property: "opacity"; to: 0; duration: 1000 }
                                }
                            }
                        }
                    }
                }
            }

            Card {
                id: toast
                anchors.horizontalCenter: parent.horizontalCenter
                y: Appearance.sizes.baseBarHeight + 24
                implicitWidth: toastRow.implicitWidth + 40
                implicitHeight: toastRow.implicitHeight + 28
                border.color: Appearance.colors.colPrimary
                border.width: 2

                // Pops in on every new celebration.
                scale: 0.6
                opacity: 0
                Connections {
                    target: root
                    function onCurrentChanged(): void {
                        pop.restart();
                    }
                }
                Component.onCompleted: pop.start()
                SequentialAnimation {
                    id: pop
                    PropertyAction { target: toast; properties: "scale,opacity"; value: 0.6 }
                    ParallelAnimation {
                        NumberAnimation { target: toast; property: "scale"; to: 1; duration: 450; easing.type: Easing.OutBack; easing.overshoot: 3 }
                        NumberAnimation { target: toast; property: "opacity"; to: 1; duration: 200 }
                    }
                    PauseAnimation { duration: 2800 }
                    NumberAnimation { target: toast; property: "opacity"; to: 0; duration: 300 }
                }

                RowLayout {
                    id: toastRow
                    anchors.centerIn: parent
                    spacing: 14
                    Rectangle {
                        implicitWidth: 48
                        implicitHeight: 48
                        radius: 24
                        color: Appearance.colors.colPrimary
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: root.current?.icon ?? ""
                            fill: 1
                            iconSize: 28
                            color: Appearance.colors.colOnPrimary
                            RotationAnimation on rotation {
                                from: -15; to: 15; duration: 400
                                loops: 4; easing.type: Easing.InOutSine
                            }
                        }
                    }
                    ColumnLayout {
                        spacing: 2
                        StyledText {
                            text: root.current?.title ?? ""
                            font.pixelSize: Appearance.font.pixelSize.huge
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer0
                        }
                        StyledText {
                            text: root.current?.subtitle ?? ""
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colPrimary
                        }
                    }
                }
            }
        }
    }

    // --- Tracker ------------------------------------------------------------
    component SectionTitle: StyledText {
        Layout.topMargin: 4
        font.pixelSize: Appearance.font.pixelSize.normal
        font.weight: Font.DemiBold
        color: Appearance.colors.colOnLayer0
    }

    // GitHub's four shades, in the theme's primary instead of green.
    function heat(minutes): color {
        if (minutes <= 0)
            return Qt.rgba(Appearance.colors.colOutlineVariant.r, Appearance.colors.colOutlineVariant.g, Appearance.colors.colOutlineVariant.b, 0.45);
        const a = minutes < 15 ? 0.3 : minutes < 45 ? 0.55 : minutes < 90 ? 0.8 : 1;
        return Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, a);
    }

    Loader {
        active: GlobalStates.studyTrackerOpen

        sourceComponent: PanelWindow {
            visible: true
            color: "transparent"
            exclusiveZone: 0
            implicitWidth: tracker.implicitWidth
            implicitHeight: tracker.implicitHeight

            WlrLayershell.namespace: "quickshell:studyTracker"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

            anchors {
                top: true
                right: true
            }
            margins {
                top: Appearance.sizes.baseBarHeight + 8
                right: 8
            }

            Item {
                focus: true
                Keys.onEscapePressed: GlobalStates.studyTrackerOpen = false
            }

            Card {
                id: tracker
                implicitWidth: 468
                implicitHeight: body.implicitHeight + 40

                // Slide + fade in, so opening it feels like something.
                opacity: 0
                transform: Translate { id: slide; y: -12 }
                Component.onCompleted: openAnim.start()
                ParallelAnimation {
                    id: openAnim
                    NumberAnimation { target: tracker; property: "opacity"; to: 1; duration: 180 }
                    NumberAnimation { target: slide; property: "y"; to: 0; duration: 260; easing.type: Easing.OutCubic }
                }

                ColumnLayout {
                    id: body
                    anchors.centerIn: parent
                    width: parent.width - 40
                    spacing: 12

                    // Header.
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        MaterialSymbol {
                            text: "school"
                            fill: 1
                            iconSize: Appearance.font.pixelSize.huge
                            color: Appearance.colors.colPrimary
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Study")
                            font.pixelSize: Appearance.font.pixelSize.larger
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer0
                        }
                        RippleButton {
                            implicitWidth: 28
                            implicitHeight: 28
                            buttonRadius: 14
                            onClicked: GlobalStates.studyTrackerOpen = false
                            contentItem: MaterialSymbol {
                                text: "close"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnLayer0
                            }
                        }
                    }

                    // Hero: level badge, rank, XP bar.
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16
                        Rectangle {
                            implicitWidth: 64
                            implicitHeight: 64
                            radius: 32
                            color: Appearance.colors.colPrimary
                            StyledText {
                                anchors.centerIn: parent
                                text: StudyMode.level
                                font.pixelSize: 30
                                font.weight: Font.Bold
                                color: Appearance.colors.colOnPrimary
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            StyledText {
                                text: StudyMode.title
                                font.pixelSize: Appearance.font.pixelSize.huge
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer0
                            }
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 10
                                radius: 5
                                color: Appearance.colors.colOutlineVariant
                                Rectangle {
                                    width: parent.width * StudyMode.levelProgress
                                    height: parent.height
                                    radius: 5
                                    color: Appearance.colors.colPrimary
                                    Behavior on width {
                                        NumberAnimation { duration: 700; easing.type: Easing.OutCubic }
                                    }
                                }
                            }
                            StyledText {
                                text: Translation.tr("%1 / 100 XP · %2 XP total").arg(StudyMode.points % 100).arg(StudyMode.points)
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnLayer1
                            }
                        }
                    }

                    // Daily goal.
                    Rectangle {
                        id: goalBox
                        Layout.fillWidth: true
                        implicitHeight: goalCol.implicitHeight + 20
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colLayer1
                        readonly property bool met: StudyMode.todayMinutes >= StudyMode.dailyGoal
                        ColumnLayout {
                            id: goalCol
                            anchors.centerIn: parent
                            width: parent.width - 24
                            spacing: 6
                            RowLayout {
                                Layout.fillWidth: true
                                StyledText {
                                    Layout.fillWidth: true
                                    text: goalBox.met ? Translation.tr("Daily goal hit 🎉") : Translation.tr("Daily goal")
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    color: Appearance.colors.colOnLayer0
                                }
                                StyledText {
                                    text: `${StudyMode.todayMinutes} / ${StudyMode.dailyGoal} min`
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    color: Appearance.colors.colPrimary
                                }
                            }
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 6
                                radius: 3
                                color: Appearance.colors.colOutlineVariant
                                Rectangle {
                                    width: parent.width * Math.min(1, StudyMode.todayMinutes / Math.max(1, StudyMode.dailyGoal))
                                    height: parent.height
                                    radius: 3
                                    color: Appearance.colors.colPrimary
                                    Behavior on width {
                                        NumberAnimation { duration: 700; easing.type: Easing.OutCubic }
                                    }
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Tile {
                            value: `🔥 ${StudyMode.streak}`
                            label: Translation.tr("day streak")
                        }
                        Tile {
                            value: `${(StudyMode.totalMinutes / 60).toFixed(1)}h`
                            label: Translation.tr("total")
                        }
                        Tile {
                            value: `${StudyMode.sessions}`
                            label: Translation.tr("sessions")
                        }
                        Tile {
                            value: `${StudyMode.badgeCount}/${StudyMode.badges.length}`
                            label: Translation.tr("badges")
                        }
                    }

                    // Contribution graph: 26 weeks, Sunday on top, this week last.
                    SectionTitle {
                        text: Translation.tr("%1 minutes in the last 6 months").arg(heatmap.total)
                    }
                    Item {
                        id: heatmap
                        Layout.fillWidth: true
                        implicitHeight: 14 + 7 * 15
                        readonly property int weeks: 26
                        readonly property real cell: (width - (weeks - 1) * 3) / weeks
                        readonly property date today: new Date(StudyMode.now * 1000)
                        readonly property real startMs: today.getTime() - (today.getDay() + (weeks - 1) * 7) * 86400000
                        readonly property int total: {
                            let t = 0;
                            for (let i = 0; i < weeks * 7; i++)
                                t += StudyMode.minutesOn(new Date(startMs + i * 86400000));
                            return t;
                        }
                        property string hoverText: ""

                        // Month labels over the first column of each month.
                        Repeater {
                            model: heatmap.weeks
                            delegate: StyledText {
                                required property int index
                                readonly property date d: new Date(heatmap.startMs + index * 7 * 86400000)
                                visible: d.getDate() <= 7
                                x: index * (heatmap.cell + 3)
                                text: Qt.formatDate(d, "MMM")
                                font.pixelSize: 10
                                color: Appearance.colors.colOnLayer1
                            }
                        }

                        Repeater {
                            model: heatmap.weeks * 7
                            delegate: Rectangle {
                                required property int index
                                readonly property int col: Math.floor(index / 7)
                                readonly property int row: index % 7
                                readonly property date d: new Date(heatmap.startMs + index * 86400000)
                                readonly property int mins: StudyMode.minutesOn(d)
                                visible: d.getTime() <= heatmap.today.getTime()
                                x: col * (heatmap.cell + 3)
                                y: 14 + row * 15
                                width: heatmap.cell
                                height: 12
                                radius: 3
                                color: root.heat(mins)
                                border.width: d.toDateString() === heatmap.today.toDateString() ? 1 : 0
                                border.color: Appearance.colors.colOnLayer0
                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onEntered: heatmap.hoverText = `${parent.mins} min on ${Qt.formatDate(parent.d, "ddd, MMM d")}`
                                    onExited: heatmap.hoverText = ""
                                }
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 3
                        StyledText {
                            Layout.fillWidth: true
                            text: heatmap.hoverText || Translation.tr("Best streak: %1 days · best day: %2 min").arg(StudyMode.bestStreak).arg(StudyMode.bestDay)
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            text: Translation.tr("Less")
                            font.pixelSize: 10
                            color: Appearance.colors.colOnLayer1
                        }
                        Repeater {
                            model: [0, 10, 30, 60, 120]
                            delegate: Rectangle {
                                required property int modelData
                                implicitWidth: 10
                                implicitHeight: 10
                                radius: 2
                                color: root.heat(modelData)
                            }
                        }
                        StyledText {
                            text: Translation.tr("More")
                            font.pixelSize: 10
                            color: Appearance.colors.colOnLayer1
                        }
                    }

                    // Badges.
                    SectionTitle {
                        text: Translation.tr("Badges")
                    }
                    GridLayout {
                        id: badgeGrid
                        Layout.fillWidth: true
                        columns: 7
                        rowSpacing: 8
                        columnSpacing: 8
                        property string hoverText: ""
                        Repeater {
                            model: StudyMode.badges
                            delegate: Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 48
                                radius: 24
                                color: modelData.got ? Appearance.colors.colPrimary : Appearance.colors.colLayer1
                                border.width: modelData.got ? 0 : 1
                                border.color: Appearance.colors.colOutlineVariant
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: parent.modelData.got ? parent.modelData.icon : "lock"
                                    fill: parent.modelData.got ? 1 : 0
                                    iconSize: 24
                                    color: parent.modelData.got ? Appearance.colors.colOnPrimary : Appearance.colors.colOutlineVariant
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onEntered: badgeGrid.hoverText = `${parent.modelData.got ? "✓" : "🔒"} ${parent.modelData.name} — ${parent.modelData.desc}`
                                    onExited: badgeGrid.hoverText = ""
                                }
                            }
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: badgeGrid.hoverText || Translation.tr("Hover a badge to see how to earn it")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer1
                    }

                    // Call to action.
                    PillButton {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        implicitHeight: 44
                        enabled: !StudyMode.active && !StudyMode.busy
                        buttonText: StudyMode.busy === "starting" ? Translation.tr("Starting…")
                            : StudyMode.busy === "stopping" ? Translation.tr("Ending…")
                            : StudyMode.active ? Translation.tr("Studying · %1 left").arg(StudyMode.remainingText)
                            : Translation.tr("Start a %1-minute session").arg(Config.options.studyMode.durationMinutes)
                        colText: Appearance.colors.colOnPrimary
                        colBackground: Appearance.colors.colPrimary
                        colBackgroundHover: Appearance.colors.colPrimaryHover
                        colRipple: Appearance.colors.colPrimaryActive
                        onClicked: {
                            GlobalStates.studyTrackerOpen = false;
                            GlobalStates.studyModeConfirmOpen = true;
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: StudyMode.active
                            ? Translation.tr("End early from Settings › General · ⌃⌥⌘S closes this")
                            : Translation.tr("1 XP per focused minute · +25 XP for finishing · ⌃⌥⌘S")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer1
                    }
                }
            }
        }
    }
}
