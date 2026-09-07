pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Cocoa as Cocoa

/**
 * Polled resource usage: RAM, swap and CPU.
 *
 * The counters come from Quickshell.Cocoa.SystemStats, an in-process
 * singleton in quickshell-macos (src/cocoa/sysstats.mm): since-boot CPU ticks
 * from host_statistics64, memory from the VM statistics and swap from
 * vm.swapusage, sampled on its own timer with nothing spawned. The property
 * surface is upstream's; sizes stay in kB.
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

    // Upstream's /proc/stat arithmetic: usage over the sample window =
    // 1 - d(idle)/d(total); the first sample only seeds it.
    function updateCpuFromTicks(total, idle) {
        if (previousCpuStats) {
            const totalDiff = total - previousCpuStats.total
            const idleDiff = idle - previousCpuStats.idle
            cpuUsage = totalDiff > 0 ? (1 - idleDiff / totalDiff) : 0
        }
        previousCpuStats = { total, idle }
    }

    // Sizes arrive in bytes; "used" is (active + wired + compressor) pages,
    // Activity Monitor's definition, and available is total minus that.
    function apply() {
        const s = Cocoa.SystemStats
        memoryTotal = s.memTotal / 1024
        memoryFree = s.memAvailable / 1024
        swapTotal = s.swapTotal / 1024
        swapFree = s.swapFree / 1024
        updateCpuFromTicks(s.cpuTotal, s.cpuIdle)
        updateHistories()
    }

    // The singleton's own timer is the sampling clock.
    Binding {
        target: Cocoa.SystemStats
        property: "interval"
        value: Config.options?.resources?.updateInterval ?? 3000
    }

    Connections {
        target: Cocoa.SystemStats
        function onSampled() { root.apply() }
    }

    // The singleton sampled once when it was created, so this seeds the tick
    // baseline immediately; the first real CPU% lands one interval later.
    Component.onCompleted: root.apply()

    // No max-frequency figure is exposed on Apple silicon, so name the chip
    // instead of inventing a GHz number.
    Process {
        command: ["/bin/sh", "-c", "sysctl -n machdep.cpu.brand_string 2>/dev/null || echo CPU"]
        running: true
        stdout: StdioCollector {
            id: outputCollector
            onStreamFinished: root.maxAvailableCpuString = outputCollector.text.trim() || "--"
        }
    }
}
