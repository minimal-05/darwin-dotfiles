pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * Provides access to some Hyprland data not available in Quickshell.Hyprland.
 */
Singleton {
    id: root
    property var windowList: []
    property var addresses: []
    property var windowByAddress: ({})
    property var workspaces: []
    property var workspaceIds: []
    property var workspaceById: ({})
    property var activeWorkspace: null
    property var monitors: []
    property var layers: ({})

    // Convenient stuff

    function toplevelsForWorkspace(workspace) {
        return ToplevelManager.toplevels.values.filter(toplevel => {
            const address = root.addressForToplevel(toplevel);
            var win = HyprlandData.windowByAddress[address];
            return win?.workspace?.id === workspace;
        })
    }

    function hyprlandClientsForWorkspace(workspace) {
        return root.windowList.filter(win => win.workspace.id === workspace);
    }

    function clientForToplevel(toplevel) {
        if (!toplevel) {
            return null;
        }
        return root.windowByAddress[root.addressForToplevel(toplevel)];
    }

    // macOS port: Quickshell.Wayland's Toplevel carries no HyprlandToplevel
    // attached property here — attached types can only be declared from C++ and
    // the Hyprland compatibility module is loose QML. The yabai window id the
    // Toplevel shim exposes as `wid` is formatted into the same "0x<hex>"
    // address the collectors below emit.
    function addressForToplevel(toplevel) {
        const wid = toplevel?.wid;
        if (wid === undefined || wid === null || wid < 0) {
            return "";
        }
        return "0x" + Number(wid).toString(16);
    }

    // Internals

    // yabai occasionally returns nothing while it is busy, and a bare
    // JSON.parse("") throws and spams the log. Fall back to the previous value.
    function parseOr(text, fallback) {
        if (!text || text.trim().length === 0)
            return fallback;
        try {
            return JSON.parse(text);
        } catch (e) {
            return fallback;
        }
    }

    function updateWindowList() {
        getClients.running = true;
    }

    function updateLayers() {
        getLayers.running = true;
    }

    function updateMonitors() {
        getMonitors.running = true;
    }

    function updateWorkspaces() {
        getWorkspaces.running = true;
        getActiveWorkspace.running = true;
    }

    function updateAll() {
        updateWindowList();
        updateMonitors();
        updateLayers();
        updateWorkspaces();
    }

    function biggestWindowForWorkspace(workspaceId) {
        const windowsInThisWorkspace = HyprlandData.windowList.filter(w => w.workspace.id == workspaceId);
        return windowsInThisWorkspace.reduce((maxWin, win) => {
            const maxArea = (maxWin?.size?.[0] ?? 0) * (maxWin?.size?.[1] ?? 0);
            const winArea = (win?.size?.[0] ?? 0) * (win?.size?.[1] ?? 0);
            return winArea > maxArea ? win : maxWin;
        }, null);
    }

    Component.onCompleted: {
        updateAll();
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            // console.log("Hyprland raw event:", event.name);
            if (["openlayer", "closelayer", "screencast"].includes(event.name)) return;
            updateAll()
        }
    }

    // macOS port: hyprctl does not exist. yabai is queried instead and its JSON
    // is reshaped into the Hyprland shapes this file already parses, so nothing
    // downstream of these collectors changes. Window addresses become
    // "0x<yabai window id>", and workspace ids become yabai space indices.
    //
    // Every field upstream emits has to be emitted here even when macOS has no
    // equivalent, because consumers distinguish "absent" from "empty". A monitor
    // on Hyprland always carries a specialWorkspace whose name is "" when none is
    // open; omitting it entirely makes `specialWorkspace?.name ?? "special"` in
    // WorkspaceModel fall through to its default and report a special workspace as
    // permanently active. yabai has no special workspaces, so the empty name is
    // both the honest answer and the one that reads correctly.
    Process {
        id: getClients
        command: ["/bin/sh", "-c", `yabai -m query --windows | jq -c 'def tohex: [recurse(if . >= 16 then ./16|floor else empty end) | . % 16] | reverse | map(if . < 10 then 48 + . else 87 + . end) | implode; [.[] | select(.app != "quickshell") | {address: ("0x" + (.id|tohex)), mapped: true, hidden: (."is-minimized" // false), at: [(.frame.x|floor), (.frame.y|floor)], size: [(.frame.w|floor), (.frame.h|floor)], workspace: {id: .space, name: (.space|tostring)}, floating: (."is-floating" // false), monitor: (.display - 1), class: .app, initialClass: .app, title: .title, initialTitle: .title, pid: .pid, focusHistoryID: 0, fullscreen: (."is-native-fullscreen" // false)}]'`]
        stdout: StdioCollector {
            id: clientsCollector
            onStreamFinished: {
                root.windowList = root.parseOr(clientsCollector.text, root.windowList)
                let tempWinByAddress = {};
                for (var i = 0; i < root.windowList.length; ++i) {
                    var win = root.windowList[i];
                    tempWinByAddress[win.address] = win;
                }
                root.windowByAddress = tempWinByAddress;
                root.addresses = root.windowList.map(win => win.address);
            }
        }
    }

    Process {
        id: getMonitors
        command: ["/bin/sh", "-c", `num() { v=$(yabai -m config "$1" 2>/dev/null); echo "$v" | grep -qE '^[0-9]+$' && echo "$v" || echo 0; }; EB=$(yabai -m config external_bar 2>/dev/null); EBT=$(echo "$EB" | cut -d: -f2 | grep -E '^[0-9]+$' || echo 0); EBB=$(echo "$EB" | cut -d: -f3 | grep -E '^[0-9]+$' || echo 0); RESERVED=$(printf '[%d,%d,%d,%d]' "$(num left_padding)" "$((EBT + $(num top_padding)))" "$(num right_padding)" "$((EBB + $(num bottom_padding)))"); SPACES=$(yabai -m query --spaces); yabai -m query --displays | jq -c --argjson spaces "$SPACES" --argjson reserved "$RESERVED" '[.[] | . as $d | {id: (.index - 1), name: ("Display-" + (.index|tostring)), description: ("Display " + (.index|tostring)), width: (.frame.w|floor), height: (.frame.h|floor), x: (.frame.x|floor), y: (.frame.y|floor), reserved: $reserved, activeWorkspace: (([$spaces[] | select(.display == $d.index and ."is-visible")] | .[0] | {id: .index, name: (.index|tostring)}) // {id:1,name:"1"}), specialWorkspace: {id: 0, name: ""}, focused: ."has-focus", scale: 1.0, transform: 0, disabled: false}]'`]
        stdout: StdioCollector {
            id: monitorsCollector
            onStreamFinished: {
                root.monitors = root.parseOr(monitorsCollector.text, root.monitors);
            }
        }
    }

    Process {
        id: getLayers
        // Layer surfaces are a Wayland concept with no macOS counterpart.
        command: ["/bin/sh", "-c", "echo '{}'"]
        stdout: StdioCollector {
            id: layersCollector
            onStreamFinished: {
                root.layers = root.parseOr(layersCollector.text, root.layers);
            }
        }
    }

    Process {
        id: getWorkspaces
        command: ["/bin/sh", "-c", `yabai -m query --spaces | jq -c '[.[] | {id: .index, name: (.index|tostring), monitor: ("Display-" + (.display|tostring)), monitorID: (.display - 1), windows: (.windows|length), hasfullscreen: false, lastwindow: "", lastwindowtitle: ""}]'`]
        stdout: StdioCollector {
            id: workspacesCollector
            onStreamFinished: {
                var rawWorkspaces = root.parseOr(workspacesCollector.text, root.workspaces);
                // Filter out invalid workspace ids (e.g. lock-screen temp workspace 2147483647 - N)
                root.workspaces = rawWorkspaces.filter(ws => ws.id >= 1 && ws.id <= 100);
                let tempWorkspaceById = {};
                for (var i = 0; i < root.workspaces.length; ++i) {
                    var ws = root.workspaces[i];
                    tempWorkspaceById[ws.id] = ws;
                }
                root.workspaceById = tempWorkspaceById;
                root.workspaceIds = root.workspaces.map(ws => ws.id);
            }
        }
    }

    Process {
        id: getActiveWorkspace
        command: ["/bin/sh", "-c", `yabai -m query --spaces --space | jq -c '{id: .index, name: (.index|tostring), monitor: ("Display-" + (.display|tostring)), monitorID: (.display - 1), windows: (.windows|length), hasfullscreen: false, lastwindow: "", lastwindowtitle: ""}'`]
        stdout: StdioCollector {
            id: activeWorkspaceCollector
            onStreamFinished: {
                root.activeWorkspace = root.parseOr(activeWorkspaceCollector.text, root.activeWorkspace);
            }
        }
    }
}
