#!/usr/bin/env python3
"""Toggle the ComicShanns font in Firefox (UI + pages) without restarting.

Talks to Firefox's remote debugging protocol on localhost and runs the same
stylesheet toggle you'd paste into the Browser Console. Firefox must have been
launched with --start-debugger-server 6543 (the ctrl+alt+cmd+G skhd binding).
"""
import json
import socket
import subprocess
import sys

PORT = 6543
TOGGLE_JS = (
    '(() => {'
    ' const sss = Cc["@mozilla.org/content/style-sheet-service;1"]'
    '.getService(Ci.nsIStyleSheetService);'
    ' const uri = Services.io.newURI("file:///Users/tylerearly/Library/'
    'Application%20Support/Firefox/Profiles/2l8opt4p.default-release/'
    'chrome/ui-font-off.css");'
    ' if (sss.sheetRegistered(uri, sss.AGENT_SHEET)) {'
    '   sss.unregisterSheet(uri, sss.AGENT_SHEET);'
    '   Services.prefs.setIntPref("browser.display.use_document_fonts", 0);'
    '   return "ON";'
    ' } else {'
    '   sss.loadAndRegisterSheet(uri, sss.AGENT_SHEET);'
    '   Services.prefs.setIntPref("browser.display.use_document_fonts", 1);'
    '   return "OFF";'
    ' }})()'
)


def notify(msg):
    subprocess.run(["osascript", "-e",
                    f'display notification "{msg}" with title "Firefox font"'])


def send(sock, obj):
    data = json.dumps(obj).encode()
    sock.sendall(str(len(data)).encode() + b":" + data)


def msgs(sock):
    buf = b""
    while True:
        while b":" not in buf:
            chunk = sock.recv(65536)
            if not chunk:
                return
            buf += chunk
        n, _, rest = buf.partition(b":")
        n = int(n)
        while len(rest) < n:
            chunk = sock.recv(65536)
            if not chunk:
                return
            rest += chunk
        yield json.loads(rest[:n])
        buf = rest[n:]


def main():
    try:
        sock = socket.create_connection(("127.0.0.1", PORT), timeout=5)
    except OSError:
        notify("No debug socket — relaunch Firefox with ctrl+alt+cmd+G")
        return 1
    sock.settimeout(10)
    try:
        it = msgs(sock)
        next(it)  # root greeting
        send(sock, {"to": "root", "type": "getProcess", "id": 0})
        msg = next(m for m in it if m.get("from") == "root"
                   and ("processDescriptor" in m or "form" in m))
        desc = msg.get("processDescriptor") or msg.get("form")
        send(sock, {"to": desc["actor"], "type": "getTarget"})
        target = next(t for m in it if m.get("from") == desc["actor"]
                      for t in [m.get("process") or m.get("frame") or m.get("target")]
                      if t)
        send(sock, {"to": target["consoleActor"],
                    "type": "evaluateJSAsync", "text": TOGGLE_JS})
        result = next(m for m in it if m.get("from") == target["consoleActor"]
                      and m.get("type") == "evaluationResult")
        notify(f"ComicShanns {result.get('result')}")
        return 0
    except Exception as exc:
        notify(f"toggle failed: {type(exc).__name__}")
        return 1
    finally:
        sock.close()


if __name__ == "__main__":
    sys.exit(main())
