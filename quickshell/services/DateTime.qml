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
    property string uptime: "0h, 0m"

    Timer {
        interval: 10
        running: true
        repeat: true
        onTriggered: {
            uptimeProc.running = true;
            interval = Config.options?.resources?.updateInterval ?? 3000;
        }
    }

    // macOS port: no /proc/uptime. kern.boottime gives the boot instant, so
    // uptime is now minus that. Emitted in the same "SECONDS IDLE" shape the
    // parsing below already expects.
    Process {
        id: uptimeProc

        running: true
        command: ["/bin/sh", "-c", "B=$(sysctl -n kern.boottime | sed -E 's/.*\\{ sec = ([0-9]+).*/\\1/'); echo \"$(( $(date +%s) - B )) 0\""]

        stdout: StdioCollector {
            id: uptimeCollector

            onStreamFinished: {
                const textUptime = uptimeCollector.text;
                const uptimeSeconds = Number(textUptime.split(" ")[0] ?? 0);

                // Convert seconds to days, hours, and minutes
                const days = Math.floor(uptimeSeconds / 86400);
                const hours = Math.floor((uptimeSeconds % 86400) / 3600);
                const minutes = Math.floor((uptimeSeconds % 3600) / 60);

                // Build the formatted uptime string
                let formatted = "";
                if (days > 0)
                    formatted += `${days}d`;
                if (hours > 0)
                    formatted += `${formatted ? ", " : ""}${hours}h`;
                if (minutes > 0 || !formatted)
                    formatted += `${formatted ? ", " : ""}${minutes}m`;
                root.uptime = formatted;
            }
        }
    }
}
