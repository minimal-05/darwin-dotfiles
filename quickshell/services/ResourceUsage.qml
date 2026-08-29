pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Simple polled resource usage service with RAM, Swap, and CPU usage.
 *
 * Linux reads /proc/meminfo and /proc/stat. macOS has neither, so the same
 * counters come from `qs-sysstats` (quickshell-macos/bin, on PATH like `qs`):
 * one JSON line of since-boot CPU ticks from host_statistics64, memory from
 * the VM statistics and swap from vm.swapusage. The ticks are cumulative like
 * the /proc/stat cpu line, so both branches diff consecutive samples the same
 * way. This replaces `top -l 1 -n 0`, which cost ~0.26 s of CPU per sample.
 * The property surface is identical to upstream; sizes stay in kB.
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

    // Upstream's /proc/stat arithmetic, shared by both branches: usage over the
    // sample window = 1 - d(idle)/d(total); the first sample only seeds it.
    function updateCpuFromTicks(total, idle) {
        if (previousCpuStats) {
            const totalDiff = total - previousCpuStats.total
            const idleDiff = idle - previousCpuStats.idle
            cpuUsage = totalDiff > 0 ? (1 - idleDiff / totalDiff) : 0
        }
        previousCpuStats = { total, idle }
    }

	Timer {
		interval: 1
        running: true
        repeat: true
		onTriggered: {
            if (Platform.isMacOS) {
                statProc.running = true
            } else {
                // Reload files
                fileMeminfo.item.reload()
                fileStat.item.reload()

                // Parse memory and swap usage
                const textMeminfo = fileMeminfo.item.text()
                memoryTotal = Number(textMeminfo.match(/MemTotal: *(\d+)/)?.[1] ?? 1)
                memoryFree = Number(textMeminfo.match(/MemAvailable: *(\d+)/)?.[1] ?? 0)
                swapTotal = Number(textMeminfo.match(/SwapTotal: *(\d+)/)?.[1] ?? 1)
                swapFree = Number(textMeminfo.match(/SwapFree: *(\d+)/)?.[1] ?? 0)

                // Parse CPU usage
                const textStat = fileStat.item.text()
                const cpuLine = textStat.match(/^cpu\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/)
                if (cpuLine) {
                    const stats = cpuLine.slice(1).map(Number)
                    const total = stats.reduce((a, b) => a + b, 0)
                    const idle = stats[3]
                    updateCpuFromTicks(total, idle)
                }

                root.updateHistories()
            }
            interval = Config.options?.resources?.updateInterval ?? 3000
        }
	}

    // /proc only exists on Linux; left inactive on macOS so nothing opens a missing path.
	Loader { id: fileMeminfo; active: !Platform.isMacOS; sourceComponent: FileView { path: "/proc/meminfo" } }
    Loader { id: fileStat; active: !Platform.isMacOS; sourceComponent: FileView { path: "/proc/stat" } }

    Process {
        id: statProc
        // Sizes arrive in bytes. "used" is (active + wired + compressor) pages,
        // Activity Monitor's definition rather than top's PhysMem line, which
        // counts file cache as used; available is total minus that.
        command: ["qs-sysstats"]
        stdout: StdioCollector {
            id: statCollector
            onStreamFinished: {
                const s = JSON.parse(statCollector.text)
                root.memoryTotal = s.mem.total / 1024
                root.memoryFree = s.mem.available / 1024
                root.swapTotal = s.swap.total / 1024
                root.swapFree = s.swap.free / 1024
                root.updateCpuFromTicks(s.cpu.user + s.cpu.system + s.cpu.idle + s.cpu.nice, s.cpu.idle)
                root.updateHistories()
            }
        }
    }

    Process {
        id: findCpuMaxFreqProc
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        // No max-frequency figure is exposed on Apple silicon, so name the chip
        // instead of inventing a GHz number.
        command: Platform.isMacOS
            ? ["/bin/sh", "-c", "sysctl -n machdep.cpu.brand_string 2>/dev/null || echo CPU"]
            : ["bash", "-c", "lscpu | grep 'CPU max MHz' | awk '{print $4}'"]
        running: true
        stdout: StdioCollector {
            id: outputCollector
            onStreamFinished: {
                root.maxAvailableCpuString = Platform.isMacOS
                    ? (outputCollector.text.trim() || "--")
                    : (parseFloat(outputCollector.text) / 1000).toFixed(0) + " GHz"
            }
        }
    }
}
