#!/usr/bin/env python3
#
# Internal-display backlight get/set for Apple Silicon Macs.
#
# There is no public API or CLI for this: the Homebrew `brightness` tool uses
# the deprecated IODisplay path and fails on Apple Silicon internal panels
# with kIOReturnUnsupported (-536870201). The only working route is the
# private DisplayServices framework, called here via ctypes so no extra
# install is required. Because this is a private, undocumented framework it
# may break on a future macOS release -- if `get`/`set` start failing after
# an OS upgrade, that is why.
#
# Usage:
#   brightness.py get         prints current brightness as a float in [0, 1]
#   brightness.py set <0..1>  sets brightness to the given float

import ctypes
import sys

CoreGraphics = ctypes.CDLL("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
DisplayServices = ctypes.CDLL("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices")
CoreGraphics.CGMainDisplayID.restype = ctypes.c_uint32


def main() -> int:
    display_id = CoreGraphics.CGMainDisplayID()

    if len(sys.argv) == 2 and sys.argv[1] == "get":
        value = ctypes.c_float()
        rc = DisplayServices.DisplayServicesGetBrightness(display_id, ctypes.byref(value))
        if rc != 0:
            print(f"error: DisplayServicesGetBrightness rc={rc}", file=sys.stderr)
            return 1
        print(f"{value.value:.4f}")
        return 0

    if len(sys.argv) == 3 and sys.argv[1] == "set":
        try:
            value = float(sys.argv[2])
        except ValueError:
            print("error: value must be a float in [0, 1]", file=sys.stderr)
            return 1
        value = max(0.0, min(1.0, value))
        rc = DisplayServices.DisplayServicesSetBrightness(display_id, ctypes.c_float(value))
        if rc != 0:
            print(f"error: DisplayServicesSetBrightness rc={rc}", file=sys.stderr)
            return 1
        return 0

    print("usage: brightness.py get | set <0.0-1.0>", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
