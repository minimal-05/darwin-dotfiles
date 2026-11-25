pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Study mode: the shell's view of scripts/study/study-mode.sh.
 *
 * The script owns the session -- it survives a shell reload, and a reboot ends
 * it -- so this only ever reads state back. `remaining` is derived from the end
 * timestamp rather than counted down here, so a reload or a slow frame cannot
 * drift it.
 */
Singleton {
    id: root

    readonly property string script: Directories.studyScriptPath

    property bool active: false
    // "starting" / "stopping" while the script runs -- a few seconds, mostly
    // Firefox restarting. The UI shows it and refuses a second click.
    property string busy: ""
    // The script's own message when start/stop fails, e.g. no allowed sites.
    property var error: null
    property int endsAt: 0
    property int now: Math.floor(Date.now() / 1000)
    readonly property int remaining: root.active ? Math.max(0, root.endsAt - root.now) : 0
    readonly property string remainingText: {
        // Zero-padded so the bar entry never changes width as it counts.
        const s = root.remaining;
        const h = Math.floor(s / 3600);
        const mm = String(Math.floor((s % 3600) / 60)).padStart(2, "0");
        const ss = String(s % 60).padStart(2, "0");
        return h > 0 ? `${h}:${mm}:${ss}` : `${mm}:${ss}`;
    }

    // Latest focus-watcher warning ({text, at}) and the lifetime tally the
    // script keeps: {points, sessions, warnings, days: {"YYYY-MM-DD": minutes}}.
    property var warn: null
    property var stats: ({})
    // False until the first status read, so loading existing stats is not
    // celebrated as fresh XP.
    property bool loaded: false

    signal gained(int xp)
    signal sessionDone()
    signal levelUp(int level, string title)
    signal unlocked(var badge)

    readonly property var titles: ["Freshman", "Apprentice", "Scholar", "Bookworm", "Honor Roll", "Dean's List", "Valedictorian", "Sage", "Professor", "Legend"]
    readonly property string title: root.titles[Math.min(root.level - 1, root.titles.length - 1)]
    readonly property int dailyGoal: Config.options.studyMode.dailyGoalMinutes
    readonly property int totalMinutes: Object.values(root.stats.days ?? {}).reduce((a, b) => a + b, 0)
    readonly property int bestStreak: {
        let best = 0, run = 0, prev = null;
        for (const key of Object.keys(root.stats.days ?? {}).sort()) {
            if ((root.stats.days[key] ?? 0) <= 0)
                continue;
            const t = new Date(key + "T12:00:00").getTime();
            run = prev !== null && Math.round((t - prev) / 86400000) === 1 ? run + 1 : 1;
            prev = t;
            best = Math.max(best, run);
        }
        return best;
    }
    readonly property int bestDay: Math.max(0, ...Object.values(root.stats.days ?? {}))
    readonly property int sessions: root.stats.sessions ?? 0

    // ponytail: badges are derived from the tally, never stored -- nothing to
    // migrate, and a badge can't get out of sync with the numbers behind it.
    readonly property var badges: [
        { id: "first", icon: "emoji_events", name: "First Steps", desc: "Study your first minute", got: root.totalMinutes >= 1 },
        { id: "s1", icon: "flag", name: "Finisher", desc: "Complete a full session", got: root.sessions >= 1 },
        { id: "s10", icon: "military_tech", name: "Regular", desc: "Complete 10 sessions", got: root.sessions >= 10 },
        { id: "s50", icon: "workspace_premium", name: "Veteran", desc: "Complete 50 sessions", got: root.sessions >= 50 },
        { id: "goal", icon: "adjust", name: "On Target", desc: "Hit your daily goal", got: root.bestDay >= root.dailyGoal },
        { id: "d120", icon: "bolt", name: "Deep Work", desc: "2 hours in one day", got: root.bestDay >= 120 },
        { id: "d240", icon: "rocket_launch", name: "Marathon", desc: "4 hours in one day", got: root.bestDay >= 240 },
        { id: "st3", icon: "local_fire_department", name: "Warming Up", desc: "3-day streak", got: root.bestStreak >= 3 },
        { id: "st7", icon: "whatshot", name: "On Fire", desc: "7-day streak", got: root.bestStreak >= 7 },
        { id: "st30", icon: "diamond", name: "Unstoppable", desc: "30-day streak", got: root.bestStreak >= 30 },
        { id: "h10", icon: "hourglass_bottom", name: "Ten Hours", desc: "10 hours total", got: root.totalMinutes >= 600 },
        { id: "h100", icon: "auto_awesome", name: "Centurion", desc: "100 hours total", got: root.totalMinutes >= 6000 },
        { id: "l5", icon: "star", name: "Rising Star", desc: "Reach level 5", got: root.level >= 5 },
        { id: "l10", icon: "social_leaderboard", name: "Legend", desc: "Reach level 10", got: root.level >= 10 },
    ]
    readonly property int badgeCount: root.badges.filter(b => b.got).length
    readonly property int points: root.stats.points ?? 0
    readonly property int level: Math.floor(root.points / 100) + 1
    readonly property real levelProgress: (root.points % 100) / 100
    readonly property int todayMinutes: root.minutesOn(new Date(root.now * 1000))
    // Last 7 days, oldest first: [{label, minutes}].
    readonly property var week: {
        const out = [];
        for (let i = 6; i >= 0; i--) {
            const d = new Date(root.now * 1000 - i * 86400000);
            out.push({ label: "SMTWTFS"[d.getDay()], minutes: root.minutesOn(d) });
        }
        return out;
    }
    // Days in a row with any focused minutes. Today not studied yet does not
    // break it -- the streak is still yours until midnight.
    readonly property int streak: {
        let n = 0;
        for (let i = root.minutesOn(new Date(root.now * 1000)) > 0 ? 0 : 1; ; i++) {
            if (root.minutesOn(new Date(root.now * 1000 - i * 86400000)) <= 0)
                return n;
            n++;
        }
    }

    function minutesOn(date): int {
        const key = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
        return root.stats.days?.[key] ?? 0;
    }

    function start(minutes): void {
        if (root.busy || root.active)
            return;
        root.busy = "starting";
        startProc.command = ["bash", root.script, "start", String(minutes)];
        startProc.running = true;
    }

    // Ending early. Not on the bar button -- Settings only, so it takes going
    // somewhere on purpose rather than one stray click on the countdown.
    function stop(): void {
        if (root.busy || !root.active)
            return;
        root.busy = "stopping";
        stopProc.command = ["bash", root.script, "stop"];
        stopProc.running = true;
    }

    // Never restarts one in flight: status can end a dead session, and killing
    // it halfway through that would leave Firefox blocked.
    function refresh(): void {
        if (!statusProc.running)
            statusProc.running = true;
    }

    function finished(stderr, exitCode): void {
        root.busy = "";
        if (exitCode !== 0)
            root.error = { text: stderr.trim() || Translation.tr("Study mode hit an error."), at: Math.floor(Date.now() / 1000) };
        root.refresh();
    }

    // One second only while a session is live; the clock is idle otherwise.
    Timer {
        running: root.active
        repeat: true
        interval: 1000
        onTriggered: {
            root.now = Math.floor(Date.now() / 1000);
            // The script's own timer ends the session; notice shortly after.
            if (root.remaining <= 0)
                root.refresh();
        }
    }

    Timer {
        running: true
        repeat: true
        // The focus watcher writes a warning at most once a minute; 5s is soon
        // enough to show it while it is still true.
        interval: root.active ? 5000 : 15000
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Process {
        id: statusProc
        command: ["bash", root.script, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    root.active = d.active === true;
                    root.endsAt = d.endsAt ?? 0;
                    root.warn = d.warn ?? null;
                    const oldPoints = root.points, oldLevel = root.level, oldSessions = root.sessions;
                    const had = root.badges.filter(b => b.got).map(b => b.id);
                    root.stats = d.stats ?? {};
                    if (root.loaded) {
                        if (root.points > oldPoints)
                            root.gained(root.points - oldPoints);
                        if (root.sessions > oldSessions)
                            root.sessionDone();
                        if (root.level > oldLevel)
                            root.levelUp(root.level, root.title);
                        for (const b of root.badges)
                            if (b.got && !had.includes(b.id))
                                root.unlocked(b);
                    }
                    root.loaded = true;
                    root.now = Math.floor(Date.now() / 1000);
                } catch (e) {
                    root.active = false;
                }
            }
        }
    }

    Process {
        id: startProc
        stderr: StdioCollector {
            id: startErr
        }
        onExited: (exitCode) => root.finished(startErr.text, exitCode)
    }

    Process {
        id: stopProc
        stderr: StdioCollector {
            id: stopErr
        }
        onExited: (exitCode) => root.finished(stopErr.text, exitCode)
    }
}
