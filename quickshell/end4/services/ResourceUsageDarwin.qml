import QtQuick
import Quickshell.Cocoa as Cocoa
import qs.modules.common
import qs.services

/**
 * The macOS sampler behind ResourceUsage: feeds it from
 * Quickshell.Cocoa.SystemStats (quickshell-macos, src/cocoa/sysstats.mm),
 * which reads host_statistics64 and vm.swapusage in-process on its own timer.
 *
 * A separate file, loaded by ResourceUsage only when Platform.isMacOS, because
 * the Quickshell.Cocoa module does not exist on Linux and an import is
 * resolved when the file is parsed, not when a branch runs. The Linux side
 * keeps reading /proc in ResourceUsage.qml itself.
 */
QtObject {
    id: root

    // Sizes arrive in bytes and ResourceUsage keeps kB, like /proc/meminfo.
    // "used" is (active + wired + compressor) pages, Activity Monitor's
    // definition rather than top's PhysMem line, which counts file cache as
    // used; available is total minus that.
    function apply() {
        const s = Cocoa.SystemStats
        ResourceUsage.memoryTotal = s.memTotal / 1024
        ResourceUsage.memoryFree = s.memAvailable / 1024
        ResourceUsage.swapTotal = s.swapTotal / 1024
        ResourceUsage.swapFree = s.swapFree / 1024
        ResourceUsage.updateCpuFromTicks(s.cpuTotal, s.cpuIdle)
        ResourceUsage.updateHistories()
    }

    // The singleton's own timer is the sampling clock; the config's interval
    // drives it directly instead of a second Timer here.
    property Binding interval: Binding {
        target: Cocoa.SystemStats
        property: "interval"
        value: Config.options?.resources?.updateInterval ?? 3000
    }

    property Connections sampler: Connections {
        target: Cocoa.SystemStats
        function onSampled() { root.apply() }
    }

    // The singleton sampled once when it was created, so this seeds the tick
    // baseline immediately; the first real CPU% lands one interval later.
    Component.onCompleted: root.apply()
}
