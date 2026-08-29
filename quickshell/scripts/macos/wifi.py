#!/usr/bin/env python3
#
# Wi-Fi association RSSI for macOS, read without triggering a scan.
#
# The obvious CLI routes are all unusable here: `airport -I` was removed in
# macOS 14.4, `wdutil info` needs sudo, and the RSSI is not published in the
# IORegistry on Apple Silicon. `system_profiler SPAirPortDataType` does print
# it, but it performs a full channel scan to do so -- that takes ~3s and takes
# the radio off its associated channel, which stalls anything streaming.
#
# CoreWLAN reads the RSSI the interface already has from its current
# association, so it neither scans nor blocks. It is a public framework, called
# here through ctypes and the Objective-C runtime so no pyobjc install is
# required -- the same approach brightness.py takes for DisplayServices.
#
# Usage:
#   wifi.py rssi    prints the association RSSI in dBm (e.g. -60)
#
# Exits 1 with no stdout when Wi-Fi is off or unassociated, so callers can
# treat "no output" as "no signal" rather than misreading a 0 dBm reading.

import ctypes
import ctypes.util
import sys

objc = ctypes.CDLL(ctypes.util.find_library("objc"))
ctypes.CDLL("/System/Library/Frameworks/CoreWLAN.framework/CoreWLAN")

objc.objc_getClass.restype = ctypes.c_void_p
objc.objc_getClass.argtypes = [ctypes.c_char_p]
objc.sel_registerName.restype = ctypes.c_void_p
objc.sel_registerName.argtypes = [ctypes.c_char_p]

# objc_msgSend has no single signature -- its return type varies per selector,
# so each call is made through a prototype cast to the type that selector
# actually returns. Getting this wrong reads garbage rather than failing.
_msg_send = ctypes.cast(objc.objc_msgSend, ctypes.c_void_p).value


def send(restype, receiver, selector: bytes):
    fn = ctypes.CFUNCTYPE(restype, ctypes.c_void_p, ctypes.c_void_p)(_msg_send)
    return fn(receiver, objc.sel_registerName(selector))


def main() -> int:
    if len(sys.argv) != 2 or sys.argv[1] != "rssi":
        print("usage: wifi.py rssi", file=sys.stderr)
        return 1

    client = send(ctypes.c_void_p, objc.objc_getClass(b"CWWiFiClient"), b"sharedWiFiClient")
    if not client:
        print("error: no CWWiFiClient", file=sys.stderr)
        return 1

    interface = send(ctypes.c_void_p, client, b"interface")
    if not interface:
        print("error: no Wi-Fi interface", file=sys.stderr)
        return 1

    if not send(ctypes.c_bool, interface, b"powerOn"):
        return 1

    # rssiValue reports 0 when the interface is powered but not associated.
    rssi = send(ctypes.c_long, interface, b"rssiValue")
    if rssi == 0:
        return 1

    print(rssi)
    return 0


if __name__ == "__main__":
    sys.exit(main())
