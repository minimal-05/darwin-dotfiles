pragma Singleton
pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * A nice wrapper for date and time strings.
 */
Singleton {
    id: root

    property var clock: SystemClock {
        id: clock
        precision: {
            if (Config.options.time.secondPrecision || GlobalStates.screenLocked)
                return SystemClock.Seconds;
            return SystemClock.Minutes;
        }
    }
    property string time: Qt.locale().toString(clock.date, Config.options?.time.format ?? "hh:mm")
    property string shortDate: Qt.locale().toString(clock.date, Config.options?.time.shortDateFormat ?? "dd/MM")
    property string date: Qt.locale().toString(clock.date, Config.options?.time.dateWithYearFormat ?? "dd/MM/yyyy")
    property string longDate: Qt.locale().toString(clock.date, Config.options?.time.dateFormat ?? "dddd, dd/MM")
    property string collapsedCalendarFormat: Qt.locale().toString(clock.date, "dddd, MMMM dd")

    // Boot instant in epoch milliseconds; 0 until the one-shot read below lands.
    property real bootTime: 0

    // The boot instant never changes, so it is read once and the uptime is
    // derived from the clock that already ticks for the time display. Uptime
    // is shown to the minute and the clock ticks at least that often, so
    // nothing needs to poll. macOS has no /proc/uptime; kern.boottime is the
    // equivalent, and /proc/stat's btime line is the same number on Linux.
    property string uptime: {
        if (root.bootTime <= 0)
            return "0h, 0m";
        const uptimeSeconds = Math.max(0, (clock.date.getTime() - root.bootTime) / 1000);
        const days = Math.floor(uptimeSeconds / 86400);
        const hours = Math.floor((uptimeSeconds % 86400) / 3600);
        const minutes = Math.floor((uptimeSeconds % 3600) / 60);

        let formatted = "";
        if (days > 0)
            formatted += `${days}d`;
        if (hours > 0)
            formatted += `${formatted ? ", " : ""}${hours}h`;
        if (minutes > 0 || !formatted)
            formatted += `${formatted ? ", " : ""}${minutes}m`;
        return formatted;
    }

    Process {
        id: bootTimeProc
        running: true
        command: Platform.isMacOS
            ? ["/usr/sbin/sysctl", "-n", "kern.boottime"]
            : ["sh", "-c", "awk '/^btime/{print \"sec = \" $2}' /proc/stat"]

        stdout: StdioCollector {
            onStreamFinished: {
                const match = text.match(/\bsec = (\d+)/);
                if (match)
                    root.bootTime = Number(match[1]) * 1000;
            }
        }
    }
}
