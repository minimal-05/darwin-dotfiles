// Probe for services/HyprlandData.qml: the four shapes populate from yabai,
// and one synthesised Hyprland event costs one refresh.
//
//   bin/qs-test <this> --binary ... -- hyprlanddata check      == ok
//   bin/qs-test <this> --binary ... -- hyprlanddata refreshes  refreshes run so far (new service only)
//   bin/qs-test <this> --binary ... -- hyprlanddata reserved   the cached yabai padding
//   bin/qs-test <this> --binary ... -- hyprlanddata summary    counts of each shape

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

ShellRoot {
    IpcHandler {
        target: "hyprlanddata"

        function check(): string {
            if (HyprlandData.windowList.length === 0) return "no-windows";
            if (HyprlandData.monitors.length === 0) return "no-monitors";
            if (HyprlandData.workspaces.length === 0) return "no-workspaces";
            if (!HyprlandData.activeWorkspace) return "no-active-workspace";
            const win = HyprlandData.windowList[0];
            if (!win.address.startsWith("0x")) return "bad-address " + win.address;
            if (HyprlandData.windowByAddress[win.address] !== win) return "bad-index";
            const mon = HyprlandData.monitors[0];
            if (!Array.isArray(mon.reserved) || mon.reserved.length !== 4) return "bad-reserved";
            if (mon.specialWorkspace?.name !== "") return "bad-special";
            return "ok";
        }

        function refreshes(): string {
            return String(HyprlandData.refreshes ?? "n/a");
        }

        function reserved(): string {
            return JSON.stringify(HyprlandData.reserved ?? null);
        }

        function summary(): string {
            return `windows=${HyprlandData.windowList.length} monitors=${HyprlandData.monitors.length} workspaces=${HyprlandData.workspaces.length} active=${HyprlandData.activeWorkspace?.id}`;
        }
    }
}
