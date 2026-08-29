pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Simple polled resource usage service with RAM, Swap, and CPU usage.
 *
 * macOS port: /proc/meminfo and /proc/stat do not exist here. A helper command
 * emits the same MemTotal/MemAvailable/SwapTotal/SwapFree keys so the parsing
 * below is unchanged, and adds a precomputed CpuUsage fraction — macOS exposes
 * no cumulative CPU tick counter to the shell, so there is nothing to diff the
 * way /proc/stat is diffed. The property surface is identical to upstream.
 */
Singleton {
    id: root
	property real memoryTotal: 1
	property real memoryFree: 0
	property real memoryUsed: memoryTotal - memoryFree
    property real memoryUsedPercentage: memoryUsed / memoryTotal
    property real swapTotal: 1
	property real swapFree: 0
	property real swapUsed: swapTotal - swapFree
    property real swapUsedPercentage: swapTotal > 0 ? (swapUsed / swapTotal) : 0
    property real cpuUsage: 0
    property var previousCpuStats

    property string maxAvailableMemoryString: kbToGbString(ResourceUsage.memoryTotal)
    property string maxAvailableSwapString: kbToGbString(ResourceUsage.swapTotal)
    property string maxAvailableCpuString: "--"

    readonly property int historyLength: Config?.options.resources.historyLength ?? 60
    property list<real> cpuUsageHistory: []
    property list<real> memoryUsageHistory: []
    property list<real> swapUsageHistory: []

    function kbToGbString(kb) {
        return (kb / (1024 * 1024)).toFixed(1) + " GB";
    }

    function updateMemoryUsageHistory() {
        memoryUsageHistory = [...memoryUsageHistory, memoryUsedPercentage]
        if (memoryUsageHistory.length > historyLength) {
            memoryUsageHistory.shift()
        }
    }
    function updateSwapUsageHistory() {
        swapUsageHistory = [...swapUsageHistory, swapUsedPercentage]
        if (swapUsageHistory.length > historyLength) {
            swapUsageHistory.shift()
        }
    }
    function updateCpuUsageHistory() {
        cpuUsageHistory = [...cpuUsageHistory, cpuUsage]
        if (cpuUsageHistory.length > historyLength) {
            cpuUsageHistory.shift()
        }
    }
    function updateHistories() {
        updateMemoryUsageHistory()
        updateSwapUsageHistory()
        updateCpuUsageHistory()
    }

	Timer {
		interval: 1
        running: true
        repeat: true
		onTriggered: {
            statProc.running = true
            interval = Config.options?.resources?.updateInterval ?? 3000
        }
	}

    Process {
        id: statProc
        running: true
        // Memory "used" follows Activity Monitor's definition, not top's PhysMem
        // line (which counts file cache as used): (active + wired + compressor) *
        // pagesize. MemAvailable is total minus that. CPU usage comes from
        // `top -l 1 -n 0`, which computes an instantaneous (not since-boot) idle
        // percentage internally -- macOS has no cumulative tick counter like
        // /proc/stat to diff ourselves.
        command: ["/bin/sh", "-c", "PAGE=$(sysctl -n hw.pagesize); TOTAL_KB=$(( $(sysctl -n hw.memsize) / 1024 )); vm_stat | awk -v page=\"$PAGE\" -v total=\"$TOTAL_KB\" '/Pages active/{gsub(/\\./,\"\",$3);act=$3} /Pages wired down/{gsub(/\\./,\"\",$4);wired=$4} /occupied by compressor/{gsub(/\\./,\"\",$5);comp=$5} END{used=(act+wired+comp)*page/1024; printf \"MemTotal: %d\\nMemAvailable: %d\\n\", total, total-used}'; sysctl -n vm.swapusage | awk '{gsub(/M/,\"\",$3); gsub(/M/,\"\",$9); printf \"SwapTotal: %d\\nSwapFree: %d\\n\", $3*1024, $9*1024}'; top -l 1 -n 0 | awk -F'[:,]' '/CPU usage/{for(i=1;i<=NF;i++) if($i ~ /idle/){gsub(/[^0-9.]/,\"\",$i); printf \"CpuUsage: %.4f\\n\", 1-($i/100)}}'"]
        stdout: StdioCollector {
            id: statCollector
            onStreamFinished: {
                const text = statCollector.text

                root.memoryTotal = Number(text.match(/MemTotal: *(\d+)/)?.[1] ?? 1)
                root.memoryFree = Number(text.match(/MemAvailable: *(\d+)/)?.[1] ?? 0)
                root.swapTotal = Number(text.match(/SwapTotal: *(\d+)/)?.[1] ?? 1)
                root.swapFree = Number(text.match(/SwapFree: *(\d+)/)?.[1] ?? 0)

                const cpu = text.match(/CpuUsage: *([\d.]+)/)
                if (cpu) root.cpuUsage = Number(cpu[1])

                root.updateHistories()
            }
        }
    }

    // No max-frequency figure is exposed on Apple silicon, so name the chip
    // instead of inventing a GHz number.
    Process {
        id: findCpuMaxFreqProc
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        command: ["/bin/sh", "-c", "sysctl -n machdep.cpu.brand_string 2>/dev/null || echo CPU"]
        running: true
        stdout: StdioCollector {
            id: outputCollector
            onStreamFinished: {
                root.maxAvailableCpuString = outputCollector.text.trim() || "--"
            }
        }
    }
}
