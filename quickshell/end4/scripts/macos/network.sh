#!/bin/bash
# Network status for macOS, printed in the shapes Network.qml already parses.
#
# nmcli does not exist here. Each subcommand below emits exactly what the
# corresponding nmcli invocation used to, so the QML parsing is unchanged:
#
#   status    lines of "<type>:<state>", then a final connectivity word
#   name      the current SSID on one line
#   strength  signal strength as 0-100
#   radio     "enabled" or "disabled"
#
# Note: macOS 15 redacts the SSID unless the calling binary has been granted
# Location Services permission, so `name` may print "<redacted>" while
# genuinely connected. That is a privacy restriction, not a failure.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

wifi_device() {
    networksetup -listallhardwareports 2>/dev/null \
        | awk '/Hardware Port: Wi-Fi/{getline; print $2; exit}'
}

default_device() {
    route -n get default 2>/dev/null | awk '/interface:/{print $2; exit}'
}

port_for() {
    networksetup -listallhardwareports 2>/dev/null \
        | awk -v dev="$1" '/Hardware Port:/{port=$0} $0 ~ "Device: "dev"$"{sub(/Hardware Port: /,"",port); print port; exit}'
}

WIFI="$(wifi_device)"
WIFI="${WIFI:-en0}"

case "${1:-status}" in
    status)
        dev="$(default_device)"
        port="$(port_for "$dev")"
        power="$(networksetup -getairportpower "$WIFI" 2>/dev/null)"

        if [[ "$power" != *": On"* ]]; then
            echo "wifi:unavailable"
        elif [[ "$port" == Wi-Fi* ]]; then
            echo "wifi:connected"
        else
            echo "wifi:disconnected"
        fi

        [[ -n "$port" && "$port" != Wi-Fi* ]] && echo "ethernet:connected"

        # scutil resolves reachability without sending traffic.
        if scutil -r 1.1.1.1 2>/dev/null | grep -q "Reachable"; then
            echo "full"
        else
            echo "none"
        fi
        ;;

    name)
        ssid="$(networksetup -getairportnetwork "$WIFI" 2>/dev/null | sed -n 's/^Current Wi-Fi Network: //p')"
        if [ -z "$ssid" ]; then
            dev="$(default_device)"
            port="$(port_for "$dev")"
            [ -n "$port" ] && ssid="$port"
        fi
        printf '%s\n' "$ssid"
        ;;

    strength)
        # RSSI in dBm mapped to nmcli's 0-100 scale.
        #
        # Read through CoreWLAN (see wifi.py), not system_profiler: the
        # SPAirPortDataType report scans every channel to build its network
        # list, which takes ~3s and holds the radio off its associated channel
        # long enough to stall streaming video. Network.qml calls this on a 10s
        # tick, so that was a video hitch every 10 seconds. wifi.py reads the
        # RSSI the current association already has, without scanning, in ~0.05s.
        rssi="$("$HERE/wifi.py" rssi 2>/dev/null)"
        if [ -z "$rssi" ]; then
            echo 0
        else
            awk -v r="$rssi" 'BEGIN{v=2*(r+100); if(v<0)v=0; if(v>100)v=100; printf "%d\n", v}'
        fi
        ;;

    radio)
        networksetup -getairportpower "$WIFI" 2>/dev/null \
            | grep -q ": On" && echo enabled || echo disabled
        ;;

    aps)
        # Unlike `strength`, this genuinely needs system_profiler's scan -- it
        # is the network list. It runs on user action, not on the status tick.
        #
        # ACTIVE:SIGNAL:FREQ:SSID:BSSID:SECURITY, one per line, matching the
        # `nmcli -g` output this is parsed as. BSSID is never exposed by
        # system_profiler, so it is left empty.
        system_profiler SPAirPortDataType 2>/dev/null | awk '
            /Current Network Information:/ { section="current"; next }
            /Other Local Wi-Fi Networks:/  { section="other";   next }
            section == "" { next }
            # An SSID line is indented 12 and ends in a colon.
            match($0, /^            [^ ].*:$/) {
                if (ssid != "") print act ":" sig ":" freq ":" ssid "::" sec
                ssid = $0; sub(/^ +/, "", ssid); sub(/:$/, "", ssid)
                act = (section == "current") ? "yes" : "no"
                sig = 0; freq = 0; sec = ""
                next
            }
            /Signal \/ Noise:/ {
                match($0, /-[0-9]+/); r = substr($0, RSTART, RLENGTH) + 0
                v = 2 * (r + 100); if (v < 0) v = 0; if (v > 100) v = 100
                sig = int(v)
            }
            /Channel:/  { freq = ($0 ~ /5GHz/) ? 5000 : ($0 ~ /6GHz/) ? 6000 : 2400 }
            /Security:/ { sec = $0; sub(/^ *Security: */, "", sec) }
            END { if (ssid != "") print act ":" sig ":" freq ":" ssid "::" sec }
        '
        ;;

    device)
        printf '%s\n' "$WIFI"
        ;;

    *)
        echo "usage: network.sh [status|name|strength|radio|device]" >&2
        exit 2
        ;;
esac
