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

    function updateWindowList() { root.refresh(); }
    function updateLayers() {}
    function updateMonitors() { root.refresh(); }
    function updateWorkspaces() { root.refresh(); }
    function updateAll() { root.refresh(); }

    // How many refreshes have run. Read by _probe_hyprlanddata.qml.
    property int refreshes: 0

    function refresh() {
        root.pending = true;
        refreshTimer.restart();
    }

    function runPending() {
        if (root.pending && !getAll.running) {
            root.pending = false;
            root.refreshes++;
            getAll.running = true;
        }
    }
    property bool pending: false

    // yabai cannot resize a window on a space macOS is not currently showing.
    // The move is recorded, the frame is not: drag a small window into an empty
    // workspace and yabai still reports the size it had in its old one, for as
    // long as you leave that space unvisited -- measured at 6s and unchanged.
    // The overview draws windows at their reported frames, so it showed the
    // window small in a corner of an otherwise empty preview.
    //
    // Re-querying cannot fix this; the data is not late, it is stale by design.
    // So where the answer is unambiguous, report where the window is going to
    // be instead: a hidden space holding exactly one tiled window gives that
    // window the whole usable area, which is what yabai will do the moment the
    // space is shown.
    //
    // ponytail: a hidden space with several windows would need bsp simulated
    // here to know the split, so those still read stale until first visited.
    // Simulate the layout if that ever matters as much as this case did.
    function settleHiddenLayout(list) {
        if (!root.monitors || root.monitors.length === 0)
            return list;

        const visible = root.monitors.map(m => m?.activeWorkspace?.id).filter(id => id !== undefined);
        const tiledByWorkspace = {};
        for (const win of list) {
            if (win?.floating || win?.hidden || win?.fullscreen)
                continue;
            const id = win?.workspace?.id;
            if (id === undefined || visible.includes(id))
                continue;
            (tiledByWorkspace[id] = tiledByWorkspace[id] ?? []).push(win);
        }

        for (const id in tiledByWorkspace) {
            const windows = tiledByWorkspace[id];
            if (windows.length !== 1)
                continue;
            const win = windows[0];
            const mon = root.monitors.find(m => m.id === win.monitor) ?? root.monitors[0];
            if (!mon?.reserved)
                continue;
            win.at = [mon.x + mon.reserved[0], mon.y + mon.reserved[1]];
            win.size = [mon.width - mon.reserved[0] - mon.reserved[2],
                        mon.height - mon.reserved[1] - mon.reserved[3]];
        }
        return list;
    }

    // getClients and getMonitors are separate processes and land in either
    // order, so the pass that parsed the windows may have had no monitors to
    // measure against. Redo it when they arrive.
    onMonitorsChanged: {
        if (root.windowList.length > 0)
            root.windowList = root.settleHiddenLayout(root.windowList.slice());
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
        getReserved.running = true;
        refresh();
    }

    // One yabai change lands here as several synthesised events (workspace,
    // workspacev2, activewindow, ...), each of which used to trigger the
    // full set of queries; the timer folds a burst into one refresh.
    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (["openlayer", "closelayer", "screencast"].includes(event.name)) return;
            root.refresh();
        }
    }

    Timer {
        id: refreshTimer
        interval: 30
        repeat: false
        onTriggered: root.runPending()
    }

    // The padding yabai reserves around the tiling area, as `reserved` on
    // every monitor: [left, top, right, bottom], external_bar folded into top
    // and bottom the way Hyprland folds a bar's exclusive zone in. Read from
    // yabai once at startup; YabaiBarSpace, which is the only writer, pushes
    // the value it wrote after every change, so the five `yabai -m config`
    // reads never run again.
    property var reserved: [0, 0, 0, 0]

    onReservedChanged: {
        if (root.monitors.length > 0)
            root.monitors = root.monitors.map(m => Object.assign({}, m, { reserved: root.reserved }));
    }

    Process {
        id: getReserved
        command: ["/bin/sh", "-c", `num() { v=$(yabai -m config "$1" 2>/dev/null); case "$v" in ''|*[!0-9]*) echo 0;; *) echo "$v";; esac; }; EB=$(yabai -m config external_bar 2>/dev/null); EBT=\${EB#*:}; EBT=\${EBT%%:*}; EBB=\${EB##*:}; case "$EBT" in ''|*[!0-9]*) EBT=0;; esac; case "$EBB" in ''|*[!0-9]*) EBB=0;; esac; printf '[%d,%d,%d,%d]' "$(num left_padding)" "$((EBT + $(num top_padding)))" "$(num right_padding)" "$((EBB + $(num bottom_padding)))"`]
        stdout: StdioCollector {
            id: reservedCollector
            onStreamFinished: {
                const v = root.parseOr(reservedCollector.text, null);
                if (Array.isArray(v) && v.length === 4)
                    root.reserved = v;
            }
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
    //
    // The three queries feed one jq (-s slurps them into [windows, spaces,
    // displays]) that emits all four shapes at once: 5 processes per refresh
    // where the per-shape pipelines cost about 38. Layers stay a constant
    // empty object — layer surfaces are a Wayland concept.
    Process {
        id: getAll
        command: ["/bin/sh", "-c", `{ yabai -m query --windows; yabai -m query --spaces; yabai -m query --displays; } | jq -c -s '`
            + `def tohex: [recurse(if . >= 16 then ./16|floor else empty end) | . % 16] | reverse | map(if . < 10 then 48 + . else 87 + . end) | implode; `
            + `def ws: {id: .index, name: (.index|tostring), monitor: ("Display-" + (.display|tostring)), monitorID: (.display - 1), windows: (.windows|length), hasfullscreen: false, lastwindow: "", lastwindowtitle: ""}; `
            + `. as [$w, $s, $d] | {`
            + `windows: [$w[] | select(.app != "quickshell") | {address: ("0x" + (.id|tohex)), mapped: true, hidden: (."is-minimized" // false), at: [(.frame.x|floor), (.frame.y|floor)], size: [(.frame.w|floor), (.frame.h|floor)], workspace: {id: .space, name: (.space|tostring)}, floating: (."is-floating" // false), monitor: (.display - 1), class: .app, initialClass: .app, title: .title, initialTitle: .title, pid: .pid, focusHistoryID: 0, fullscreen: (."is-native-fullscreen" // false)}], `
            + `workspaces: [$s[] | ws], `
            + `activeWorkspace: (([$s[] | select(."has-focus")] | .[0]) as $a | if $a then ($a | ws) else null end), `
            + `monitors: [$d[] | . as $dd | {id: (.index - 1), name: ("Display-" + (.index|tostring)), description: ("Display " + (.index|tostring)), width: (.frame.w|floor), height: (.frame.h|floor), x: (.frame.x|floor), y: (.frame.y|floor), activeWorkspace: (([$s[] | select(.display == $dd.index and ."is-visible")] | .[0] | {id: .index, name: (.index|tostring)}) // {id:1,name:"1"}), specialWorkspace: {id: 0, name: ""}, focused: ."has-focus", scale: 1.0, transform: 0, disabled: false}]`
            + `}'`]
        onRunningChanged: if (!running) Qt.callLater(root.runPending)
        stdout: StdioCollector {
            id: allCollector
            onStreamFinished: {
                const data = root.parseOr(allCollector.text, null);
                if (!data || typeof data !== "object")
                    return;

                // Monitors first: settleHiddenLayout measures windows against
                // them. `reserved` is stamped here rather than passed to jq so
                // the command never changes under a running process.
                if (Array.isArray(data.monitors))
                    root.monitors = data.monitors.map(m => Object.assign(m, { reserved: root.reserved }));

                if (Array.isArray(data.windows)) {
                    root.windowList = root.settleHiddenLayout(data.windows);
                    let tempWinByAddress = {};
                    for (var i = 0; i < root.windowList.length; ++i) {
                        var win = root.windowList[i];
                        tempWinByAddress[win.address] = win;
                    }
                    root.windowByAddress = tempWinByAddress;
                    root.addresses = root.windowList.map(win => win.address);
                }

                if (Array.isArray(data.workspaces)) {
                    // Filter out invalid workspace ids (e.g. lock-screen temp workspace 2147483647 - N)
                    root.workspaces = data.workspaces.filter(ws => ws.id >= 1 && ws.id <= 100);
                    let tempWorkspaceById = {};
                    for (var j = 0; j < root.workspaces.length; ++j) {
                        var ws = root.workspaces[j];
                        tempWorkspaceById[ws.id] = ws;
                    }
                    root.workspaceById = tempWorkspaceById;
                    root.workspaceIds = root.workspaces.map(ws => ws.id);
                }

                if (data.activeWorkspace)
                    root.activeWorkspace = data.activeWorkspace;
            }
        }
    }
}
