pragma Singleton
pragma ComponentBehavior: Bound

// Took many bits from https://github.com/caelestia-dots/shell (GPLv3)

import Quickshell
import Quickshell.Io
import QtQuick
import qs.modules.common
import qs.services.network

/**
 * Network service.
 *
 * macOS port: nmcli does not exist. scripts/macos/network.sh prints the same
 * shapes this file already parses, using networksetup, route, scutil and
 * system_profiler. The nmcli event subscriber becomes a plain ticker — macOS
 * has no network event stream to subscribe to. Each tick is one
 * `network.sh all` (status, name, strength, radio from a single process);
 * the access-point list (`aps`, a 3 s radio scan) is only fetched when a
 * Wi-Fi panel asks for it via rescanWifi(), never at startup.
 *
 * The SSID reads as "<redacted>" (falling back to "Wi-Fi") unless quickshell is
 * granted Location Services permission; that is a macOS privacy restriction.
 */
Singleton {
    id: root

    property bool wifi: true
    property bool ethernet: false

    property bool wifiEnabled: false
    property bool wifiScanning: false
    property bool wifiConnecting: connectProc.running
    property WifiAccessPoint wifiConnectTarget
    readonly property list<WifiAccessPoint> wifiNetworks: []
    readonly property WifiAccessPoint active: wifiNetworks.find(n => n.active) ?? null
    readonly property list<var> friendlyWifiNetworks: [...wifiNetworks].sort((a, b) => {
        if (a.active && !b.active)
            return -1;
        if (!a.active && b.active)
            return 1;
        return b.strength - a.strength;
    })
    property string wifiStatus: "disconnected"

    property string networkName: ""
    property int networkStrength
    // The scanned list only exists after a Wi-Fi panel has been opened, so
    // the icon falls back to the strength the status tick reads.
    readonly property int activeStrength: root.active?.strength ?? root.networkStrength
    property string materialSymbol: root.ethernet
        ? "lan"
        : (root.wifiEnabled && root.wifiStatus === "connected")
            ? (
                root.activeStrength > 83 ? "signal_wifi_4_bar" :
                root.activeStrength > 67 ? "network_wifi" :
                root.activeStrength > 50 ? "network_wifi_3_bar" :
                root.activeStrength > 33 ? "network_wifi_2_bar" :
                root.activeStrength > 17 ? "network_wifi_1_bar" :
                "signal_wifi_0_bar"
            )
            : (root.wifiStatus === "connecting")
                ? "signal_wifi_statusbar_not_connected"
                : (root.wifiStatus === "disconnected")
                    ? "wifi_find"
                    : (root.wifiStatus === "disabled")
                        ? "signal_wifi_off"
                        : "signal_wifi_bad"

    // Control
    function enableWifi(enabled = true): void {
        const cmd = enabled ? "on" : "off";
        enableWifiProc.exec(["bash", "-c", `networksetup -setairportpower "$(bash ${Directories.networkScriptPath} device)" ${cmd}`]);
    }

    function toggleWifi(): void {
        enableWifi(!wifiEnabled);
    }

    function rescanWifi(): void {
        wifiScanning = true;
        getNetworks.running = true;
    }

    function connectToWifiNetwork(accessPoint: WifiAccessPoint): void {
        accessPoint.askingPassword = false;
        root.wifiConnectTarget = accessPoint;
        // We use this instead of `nmcli connection up SSID` because this also creates a connection profile
        connectProc.exec(["bash", "-c", `networksetup -setairportnetwork "$(bash ${Directories.networkScriptPath} device)" "${accessPoint.ssid}"`])

    }

    function disconnectWifiNetwork(): void {
        // macOS has no per-network disconnect; cycling the radio is the only way off.
        if (active) disconnectProc.exec(["bash", "-c", `D="$(bash ${Directories.networkScriptPath} device)"; networksetup -setairportpower "$D" off; sleep 1; networksetup -setairportpower "$D" on`]);
    }

    function openPublicWifiPortal() {
        Quickshell.execDetached(["xdg-open", "https://nmcheck.gnome.org/"]) // From some StackExchange thread, seems to work
    }

    function changePassword(network: WifiAccessPoint, password: string, username = ""): void {
        // TODO: enterprise wifi with username
        network.askingPassword = false;
        changePasswordProc.exec({
            "environment": {
                "PASSWORD": password,
                "SSID": network.ssid
            },
            // macOS stores the PSK in the login keychain as part of joining, so
            // there is no separate "modify the saved password" step.
            "command": ["bash", "-c", 'networksetup -setairportnetwork "$(bash ' + Directories.networkScriptPath + ' device)" "$SSID" "$PASSWORD"']
        })
    }

    Process {
        id: enableWifiProc
    }

    Process {
        id: connectProc
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        stdout: SplitParser {
            onRead: line => {
                // print(line)
                getNetworks.running = true
            }
        }
        stderr: SplitParser {
            onRead: line => {
                // print("err:", line)
                if (line.includes("Secrets were required")) {
                    root.wifiConnectTarget.askingPassword = true
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            root.wifiConnectTarget.askingPassword = (exitCode !== 0)
            root.wifiConnectTarget = null
            root.update()
        }
    }

    Process {
        id: disconnectProc
        stdout: SplitParser {
            onRead: getNetworks.running = true
        }
        onExited: root.update()
    }

    Process {
        id: changePasswordProc
        onExited: { // Re-attempt connection after changing password
            connectProc.running = false
            connectProc.running = true
        }
    }

    // Status update
    property int updateInterval: 30000

    function update() {
        updateAll.running = true;
    }

    Timer {
        interval: root.updateInterval
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.update()
    }

    Process {
        id: updateAll
        command: ["bash", Directories.networkScriptPath, "all"]
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        stdout: StdioCollector {
            onStreamFinished: {
                let hasEthernet = false;
                let hasWifi = false;
                let wifiStatus = "disconnected";
                let connectivity = "none"; // none, limited, full
                const statusLines = [];

                for (const raw of text.trim().split("\n")) {
                    const sep = raw.indexOf(" ");
                    if (sep < 0) continue;
                    const key = raw.slice(0, sep);
                    const value = raw.slice(sep + 1);
                    if (key === "status") statusLines.push(value);
                    else if (key === "name") root.networkName = value;
                    else if (key === "strength") root.networkStrength = parseInt(value) || 0;
                    else if (key === "radio") root.wifiEnabled = value.trim() === "enabled";
                }
                if (statusLines.length > 0)
                    connectivity = statusLines.pop();

                statusLines.forEach(line => {
                    if (line.includes("ethernet") && line.includes("connected"))
                        hasEthernet = true;
                    else if (line.includes("wifi:")) {
                        if (line.includes("disconnected")) {
                            wifiStatus = "disconnected"
                        }
                        else if (line.includes("connected")) {
                            hasWifi = true;
                            wifiStatus = "connected"

                            if (connectivity === "limited") {
                                hasWifi = false;
                                wifiStatus = "limited"
                            }
                        }
                        else if (line.includes("connecting")) {
                            wifiStatus = "connecting"
                        }
                        else if (line.includes("unavailable")) {
                            wifiStatus = "disabled"
                        }
                    }
                });
                root.wifiStatus = wifiStatus;
                root.ethernet = hasEthernet;
                root.wifi = hasWifi;
            }
        }
    }

    Process {
        id: getNetworks
        // Never at startup: this is the 3 s channel scan. rescanWifi() runs it
        // when a Wi-Fi panel opens; connect/disconnect refresh it after.
        running: false
        command: ["bash", Directories.networkScriptPath, "aps"]
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        stdout: StdioCollector {
            onStreamFinished: {
                root.wifiScanning = false;
                const PLACEHOLDER = "STRINGWHICHHOPEFULLYWONTBEUSED";
                const rep = new RegExp("\\\\:", "g");
                const rep2 = new RegExp(PLACEHOLDER, "g");

                const allNetworks = text.trim().split("\n").map(n => {
                    const net = n.replace(rep, PLACEHOLDER).split(":");
                    return {
                        active: net[0] === "yes",
                        strength: parseInt(net[1]),
                        frequency: parseInt(net[2]),
                        ssid: net[3],
                        bssid: net[4]?.replace(rep2, ":") ?? "",
                        security: net[5] || ""
                    };
                }).filter(n => n.ssid && n.ssid.length > 0);

                // Group networks by SSID and prioritize connected ones
                const networkMap = new Map();
                for (const network of allNetworks) {
                    const existing = networkMap.get(network.ssid);
                    if (!existing) {
                        networkMap.set(network.ssid, network);
                    } else {
                        // Prioritize active/connected networks
                        if (network.active && !existing.active) {
                            networkMap.set(network.ssid, network);
                        } else if (!network.active && !existing.active) {
                            // If both are inactive, keep the one with better signal
                            if (network.strength > existing.strength) {
                                networkMap.set(network.ssid, network);
                            }
                        }
                        // If existing is active and new is not, keep existing
                    }
                }

                const wifiNetworks = Array.from(networkMap.values());

                const rNetworks = root.wifiNetworks;

                const destroyed = rNetworks.filter(rn => !wifiNetworks.find(n => n.frequency === rn.frequency && n.ssid === rn.ssid && n.bssid === rn.bssid));
                for (const network of destroyed)
                    rNetworks.splice(rNetworks.indexOf(network), 1).forEach(n => n.destroy());

                for (const network of wifiNetworks) {
                    const match = rNetworks.find(n => n.frequency === network.frequency && n.ssid === network.ssid && n.bssid === network.bssid);
                    if (match) {
                        match.lastIpcObject = network;
                    } else {
                        rNetworks.push(apComp.createObject(root, {
                            lastIpcObject: network
                        }));
                    }
                }
            }
        }
    }

    Component {
        id: apComp

        WifiAccessPoint {}
    }
}
