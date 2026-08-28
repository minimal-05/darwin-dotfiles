// Control Center panel: Apple CC grid layout in the bar's M3 theme.
// Single instance: launching while running closes the running one (toggle).
import AppKit

// MARK: - Theme
let COL_BG = NSColor(red: 0x21/255.0, green: 0x1F/255.0, blue: 0x26/255.0, alpha: 0.98)
let COL_CARD = NSColor(red: 0x2B/255.0, green: 0x29/255.0, blue: 0x30/255.0, alpha: 1)
let COL_HOVER = NSColor(red: 0x3B/255.0, green: 0x38/255.0, blue: 0x46/255.0, alpha: 1)
let COL_OUTLINE = NSColor(red: 0x49/255.0, green: 0x45/255.0, blue: 0x4F/255.0, alpha: 1)
let COL_PRIMARY = NSColor(red: 0xD0/255.0, green: 0xBC/255.0, blue: 0xFF/255.0, alpha: 1)
let COL_ON_PRIMARY = NSColor(red: 0x38/255.0, green: 0x1E/255.0, blue: 0x72/255.0, alpha: 1)
let COL_TEXT = NSColor(red: 0xE6/255.0, green: 0xE0/255.0, blue: 0xE9/255.0, alpha: 1)
let COL_MUTED = NSColor(red: 0xCA/255.0, green: 0xC4/255.0, blue: 0xD0/255.0, alpha: 1)
let COL_YELLOW = NSColor(red: 0xE8/255.0, green: 0xC4/255.0, blue: 0x8A/255.0, alpha: 1)
let COL_TEAL = NSColor(red: 0x8F/255.0, green: 0xD5/255.0, blue: 0xCB/255.0, alpha: 1)

let PANEL_W: CGFloat = 320
let PAD: CGFloat = 12
let BREW = "/opt/homebrew/bin/"

// MARK: - Brightness via private DisplayServices (works on Apple Silicon;
// the `brightness` CLI cannot touch these panels at all)
typealias DSGetFn = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
typealias DSSetFn = @convention(c) (UInt32, Float) -> Int32
let dsGetBrightness: DSGetFn? = {
    guard let h = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW),
          let sym = dlsym(h, "DisplayServicesGetBrightness") else { return nil }
    return unsafeBitCast(sym, to: DSGetFn.self)
}()
let dsSetBrightness: DSSetFn? = {
    guard let h = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW),
          let sym = dlsym(h, "DisplayServicesSetBrightness") else { return nil }
    return unsafeBitCast(sym, to: DSSetFn.self)
}()

// MARK: - Shell
func sh(_ cmd: String, _ done: ((String) -> Void)? = nil) {
    DispatchQueue.global().async {
        let p = Process()
        p.launchPath = "/bin/sh"
        p.arguments = ["-c", cmd]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        try? p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let out = String(data: data, encoding: .utf8) ?? ""
        if let done = done { DispatchQueue.main.async { done(out) } }
    }
}

func shq(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

// MARK: - Views
final class FlipView: NSView { override var isFlipped: Bool { true } }

final class ClickView: NSView {
    override var isFlipped: Bool { true } // draw top-down like the container
    var onClick: (() -> Void)?
    var hoverColor: NSColor?
    var baseColor: NSColor?
    private var tracking: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(t); tracking = t
    }
    override func mouseEntered(with event: NSEvent) {
        if let h = hoverColor { layer?.backgroundColor = h.cgColor }
    }
    override func mouseExited(with event: NSEvent) {
        if let b = baseColor { layer?.backgroundColor = b.cgColor }
    }
    override func mouseDown(with event: NSEvent) { onClick?() }
}

// M3 track: outline-colored bar, lavender fill, white knob — instead of the
// system-accent tint NSSlider paints by default
final class M3SliderCell: NSSliderCell {
    var fillColor: NSColor = COL_PRIMARY
    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let track = NSRect(x: rect.minX, y: rect.midY - 3, width: rect.width, height: 6)
        NSBezierPath(roundedRect: track, xRadius: 3, yRadius: 3).addClip()
        COL_OUTLINE.setFill()
        track.fill()
        let pct = CGFloat((doubleValue - minValue) / (maxValue - minValue))
        fillColor.setFill()
        NSRect(x: track.minX, y: track.minY, width: track.width * pct, height: 6).fill()
    }
    override func drawKnob(_ knobRect: NSRect) {
        let r = knobRect.insetBy(dx: 4, dy: 4)
        NSColor.white.setFill()
        NSBezierPath(ovalIn: r).fill()
    }
}

// Slider that knows when it's being dragged (tracking runs inside mouseDown),
// so renders can be deferred and the final value is always sent on release.
final class DragSlider: NSSlider {
    var dragging = false
    var onDragEnd: (() -> Void)?
    override func mouseDown(with event: NSEvent) {
        dragging = true
        super.mouseDown(with: event)
        dragging = false
        if let a = action { sendAction(a, to: target) } // exact final value
        onDragEnd?()
    }
}

func card(_ frame: NSRect, radius: CGFloat = 12, color: NSColor = COL_CARD) -> ClickView {
    let v = ClickView(frame: frame)
    v.wantsLayer = true
    v.layer?.backgroundColor = color.cgColor
    v.layer?.cornerRadius = radius
    v.baseColor = color
    v.hoverColor = COL_HOVER
    return v
}

func label(_ text: String, size: CGFloat, color: NSColor, weight: NSFont.Weight = .regular) -> NSTextField {
    let l = NSTextField(labelWithString: text)
    l.font = .systemFont(ofSize: size, weight: weight)
    l.textColor = color
    l.lineBreakMode = .byTruncatingTail
    return l
}

func circleIcon(_ symbol: String, on: Bool, size: CGFloat = 30) -> NSView {
    let v = NSView(frame: NSRect(x: 0, y: 0, width: size, height: size))
    v.wantsLayer = true
    v.layer?.cornerRadius = size / 2
    v.layer?.backgroundColor = (on ? COL_PRIMARY : COL_HOVER).cgColor
    let img = NSImageView(frame: v.bounds.insetBy(dx: size * 0.22, dy: size * 0.22))
    if let i = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
        img.image = i
        img.contentTintColor = on ? COL_ON_PRIMARY : COL_MUTED
        img.imageScaling = .scaleProportionallyUpOrDown
    }
    v.addSubview(img)
    return v
}

// MARK: - State
struct SysState {
    var wifi = false
    var bt = false
    var airdrop = "Off"
    var dark = false
    var night = false
    var volume = 50
    var mediaTitle: String? = nil
    var mediaPlaying = false
    var networks: [String] = []
    var devices: [(name: String, address: String, connected: Bool)] = []
}

// MARK: - App
final class App: NSObject, NSApplicationDelegate {
    var panel: NSPanel!
    var content: FlipView!
    var state = SysState()
    var view = "main"
    var monitor: Any?
    var timer: Timer?
    var sigSrc: DispatchSourceSignal?
    var startHidden = false
    var fadeNext = false
    var shown = false
    var renderQueued = false
    var renderPendingAfterDrag = false
    var brightnessVal = 50
    var lastVolSent = -1
    var lastBrightSent = -1
    lazy var brightSlider: DragSlider = makeSlider(action: #selector(brightnessChanged(_:)), fill: COL_YELLOW)
    lazy var soundSlider: DragSlider = makeSlider(action: #selector(volumeChanged(_:)))

    func makeSlider(action: Selector, fill: NSColor = COL_PRIMARY) -> DragSlider {
        let sl = DragSlider(frame: .zero)
        let cell = M3SliderCell()
        cell.fillColor = fill
        sl.cell = cell
        sl.minValue = 0
        sl.maxValue = 100
        sl.isContinuous = true
        sl.target = self
        sl.action = action
        sl.onDragEnd = { [weak self] in
            guard let self = self else { return }
            if self.renderPendingAfterDrag {
                self.renderPendingAfterDrag = false
                self.render()
            }
        }
        return sl
    }

    var anyDragging: Bool { brightSlider.dragging || soundSlider.dragging }

    // Coalesce the burst of async state callbacks into one render; never
    // rebuild the view under an active slider drag.
    func scheduleRender() {
        if anyDragging { renderPendingAfterDrag = true; return }
        if renderQueued { return }
        renderQueued = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            self.renderQueued = false
            if self.anyDragging { self.renderPendingAfterDrag = true; return }
            self.render()
        }
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: PANEL_W, height: 400),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isFloatingPanel = true

        content = FlipView(frame: panel.contentView!.bounds)
        content.autoresizingMask = [.width, .height]
        content.wantsLayer = true
        content.layer?.backgroundColor = COL_BG.cgColor
        content.layer?.cornerRadius = 18
        content.layer?.borderWidth = 1
        content.layer?.borderColor = COL_OUTLINE.cgColor
        panel.contentView!.addSubview(content)

        refreshAll() // pre-warm state even when starting hidden
        if !startHidden { render() }

        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self = self else { return }
            // clicks in the bar strip don't auto-hide: the gear's toggle signal
            // is the sole authority there (otherwise a tap hides AND toggles)
            if let scr = NSScreen.main, NSEvent.mouseLocation.y > scr.frame.maxY - 56 { return }
            self.hidePanel()
        }
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            if e.keyCode == 53 { self?.hidePanel(); return nil }
            return e
        }
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self = self, self.panel.isVisible else { return }
            self.refreshAll()
        }
        // resident: a second launch sends SIGUSR1 to toggle instantly
        signal(SIGUSR1, SIG_IGN)
        sigSrc = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        sigSrc?.setEventHandler { [weak self] in self?.togglePanel() }
        sigSrc?.resume()
    }

    var lastHide = Date.distantPast
    func hidePanel() {
        guard panel.isVisible else { return }
        lastHide = Date()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: { self.panel.orderOut(nil) })
    }

    func togglePanel() {
        if panel.isVisible {
            hidePanel()
        } else if Date().timeIntervalSince(lastHide) < 0.35 {
            return // this tap already hid the panel; don't bounce it back open
        } else {
            shown = false // re-run the drop-in entrance
            view = "main"
            refreshAll()
            fadeNext = true
            render()
        }
    }

    func place(height: CGFloat) {
        guard let screen = NSScreen.main else { return }
        let f = screen.frame
        let x = f.maxX - PANEL_W - 14
        let y = f.maxY - 52 - height // bar: y_offset 8 + height 38 + gap 6
        let target = NSRect(x: x, y: y, width: PANEL_W, height: height)
        if !shown {
            // first show: position at the target BEFORE ordering front, then a
            // short drop-in from the bar — never a fly-in from the old frame
            shown = true
            panel.setFrame(target.offsetBy(dx: 0, dy: 12), display: false)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.38, 1.1, 0.22, 1)
                panel.animator().setFrame(target, display: true)
                panel.animator().alphaValue = 1
            }
        } else {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.38, 1.1, 0.22, 1)
                panel.animator().setFrame(target, display: true)
            }
        }
    }

    // MARK: refresh
    func refreshAll() {
        if !brightSlider.dragging, let get = dsGetBrightness {
            var b: Float = 0
            if get(CGMainDisplayID(), &b) == 0 {
                brightnessVal = Int((b * 100).rounded())
            }
        }
        sh("networksetup -getairportpower en0") { self.state.wifi = $0.contains("On"); self.scheduleRender() }
        sh(BREW + "blueutil -p") { self.state.bt = $0.contains("1"); self.scheduleRender() }
        sh("defaults read com.apple.sharingd DiscoverableMode 2>/dev/null || echo Off") {
            let m = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            self.state.airdrop = (m == "Contacts Only" || m == "Everyone") ? m : "Off"
            self.scheduleRender()
        }
        sh("defaults read -g AppleInterfaceStyle 2>/dev/null || echo Light") { self.state.dark = $0.contains("Dark"); self.scheduleRender() }
        sh(BREW + "nightlight status 2>/dev/null || echo off") { self.state.night = $0.hasPrefix("on"); self.scheduleRender() }
        sh("osascript -e 'output volume of (get volume settings)'") {
            if !self.soundSlider.dragging {
                self.state.volume = Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 50
            }
            self.scheduleRender()
        }
        sh("cat /tmp/sketchybar_media.json 2>/dev/null") { out in
            self.state.mediaTitle = nil
            if let data = out.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let d = (json["payload"] as? [String: Any]) ?? json
                self.state.mediaTitle = d["title"] as? String
                self.state.mediaPlaying = d["playing"] as? Bool ?? false
            }
            self.scheduleRender()
        }
        sh("networksetup -listpreferredwirelessnetworks en0 2>/dev/null | sed 1d") { out in
            self.state.networks = out.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            self.state.networks = Array(self.state.networks.prefix(6))
            self.scheduleRender()
        }
        sh(BREW + "blueutil --paired --format json 2>/dev/null") { out in
            self.state.devices = []
            if let data = out.data(using: .utf8),
               let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                for d in arr.prefix(5) {
                    self.state.devices.append((d["name"] as? String ?? "device",
                                               d["address"] as? String ?? "",
                                               d["connected"] as? Bool ?? false))
                }
            }
            self.scheduleRender()
        }
    }

    // MARK: render
    func render() {
        content.subviews.forEach { $0.removeFromSuperview() }
        let h: CGFloat = view == "main" ? renderMain() : renderSub(wifi: view == "wifi")
        if fadeNext {
            fadeNext = false
            for v in content.subviews { v.alphaValue = 0 }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                for v in content.subviews { v.animator().alphaValue = 1 }
            }
        }
        place(height: h)
    }

    func moduleRow(in parent: NSView, y: CGFloat, symbol: String, on: Bool, title: String, sub: String,
                   circleTap: @escaping () -> Void, rowTap: (() -> Void)? = nil) {
        let circle = circleIcon(symbol, on: on)
        circle.setFrameOrigin(NSPoint(x: 10, y: y))
        let tap = ClickView(frame: NSRect(x: 10, y: y, width: 30, height: 30))
        tap.onClick = circleTap
        let t = label(title, size: 12, color: COL_TEXT, weight: .semibold)
        t.frame = NSRect(x: 50, y: y + 1, width: 88, height: 15)
        let s = label(sub, size: 10, color: COL_MUTED)
        s.frame = NSRect(x: 50, y: y + 16, width: 88, height: 13)
        let rowHit = ClickView(frame: NSRect(x: 44, y: y - 4, width: 98, height: 38))
        rowHit.onClick = rowTap ?? circleTap
        parent.addSubview(t); parent.addSubview(s)
        parent.addSubview(circle); parent.addSubview(tap); parent.addSubview(rowHit)
    }

    func renderMain() -> CGFloat {
        var y: CGFloat = PAD
        // left card: wifi / bt / airdrop
        let left = card(NSRect(x: PAD, y: y, width: 148, height: 158))
        left.hoverColor = nil
        moduleRow(in: left, y: 12, symbol: state.wifi ? "wifi" : "wifi.slash", on: state.wifi,
                  title: "Wi-Fi", sub: state.wifi ? "On" : "Off",
                  circleTap: { [self] in
                      sh("networksetup -setairportpower en0 " + (state.wifi ? "off" : "on")) { _ in self.refreshAll() }
                  },
                  rowTap: { [self] in view = "wifi"; fadeNext = true; render() })
        moduleRow(in: left, y: 64, symbol: "b.circle.fill", on: state.bt,
                  title: "Bluetooth", sub: state.bt ? "On" : "Off",
                  circleTap: { [self] in sh(BREW + "blueutil -p toggle") { _ in self.refreshAll() } },
                  rowTap: { [self] in view = "bt"; fadeNext = true; render() })
        moduleRow(in: left, y: 116, symbol: "dot.radiowaves.left.and.right", on: state.airdrop != "Off",
                  title: "AirDrop", sub: state.airdrop,
                  circleTap: { [self] in
                      let next = ["Off": "Contacts Only", "Contacts Only": "Everyone", "Everyone": "Off"][state.airdrop] ?? "Off"
                      sh("defaults write com.apple.sharingd DiscoverableMode -string \(shq(next)) && killall sharingd 2>/dev/null") { _ in
                          DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.refreshAll() }
                      }
                  })
        content.addSubview(left)

        // right column: sleep card + two tiles
        let sleep = card(NSRect(x: 170, y: y, width: 138, height: 64))
        sleep.onClick = { [self] in sh("pmset sleepnow"); hidePanel() }
        let sc = circleIcon("bed.double.fill", on: true)
        sc.layer?.backgroundColor = COL_TEAL.cgColor
        sc.setFrameOrigin(NSPoint(x: 10, y: 17))
        sleep.addSubview(sc)
        let st = label("Sleep", size: 12, color: COL_TEXT, weight: .semibold)
        st.frame = NSRect(x: 50, y: 24, width: 80, height: 15)
        sleep.addSubview(st)
        content.addSubview(sleep)

        func tile(x: CGFloat, symbol: String, title: String, on: Bool, tap: @escaping () -> Void) {
            let t = card(NSRect(x: x, y: y + 74, width: 64, height: 84))
            t.onClick = tap
            let c = circleIcon(symbol, on: on, size: 28)
            c.setFrameOrigin(NSPoint(x: 18, y: 12))
            t.addSubview(c)
            let l = label(title, size: 9, color: COL_MUTED)
            l.alignment = .center
            l.frame = NSRect(x: 2, y: 46, width: 60, height: 30)
            l.maximumNumberOfLines = 2
            l.lineBreakMode = .byWordWrapping
            t.addSubview(l)
            content.addSubview(t)
        }
        tile(x: 170, symbol: "circle.lefthalf.filled", title: "Dark Mode", on: state.dark) { [self] in
            sh("osascript -e 'tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode'") { _ in self.refreshAll() }
        }
        tile(x: 244, symbol: "moon.stars.fill", title: "Night Shift", on: state.night) { [self] in
            sh(BREW + "nightlight toggle") { _ in self.refreshAll() }
        }
        y += 158 + 10

        // display + sound slider cards — sliders persist across renders so a
        // drag is never interrupted by a rebuild
        func sliderCard(title: String, symbol: String, slider: DragSlider, value: Int, tint: NSColor) -> CGFloat {
            let c = card(NSRect(x: PAD, y: y, width: PANEL_W - 2 * PAD, height: 62))
            c.hoverColor = nil
            let t = label(title, size: 12, color: COL_TEXT, weight: .semibold)
            t.frame = NSRect(x: 12, y: 8, width: 200, height: 15)
            c.addSubview(t)
            let ic = NSImageView(frame: NSRect(x: 12, y: 32, width: 16, height: 16))
            ic.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            ic.contentTintColor = tint
            c.addSubview(ic)
            slider.removeFromSuperview()
            slider.frame = NSRect(x: 34, y: 30, width: PANEL_W - 2 * PAD - 46, height: 20)
            if !slider.dragging { slider.integerValue = value }
            c.addSubview(slider)
            content.addSubview(c)
            y += 62 + 10
            return y
        }
        _ = sliderCard(title: "Display", symbol: "sun.max.fill", slider: brightSlider, value: brightnessVal, tint: COL_YELLOW)
        _ = sliderCard(title: "Sound", symbol: state.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill",
                       slider: soundSlider, value: state.volume, tint: COL_MUTED)

        // media card
        let m = card(NSRect(x: PAD, y: y, width: PANEL_W - 2 * PAD, height: 56))
        m.hoverColor = nil
        let box = NSView(frame: NSRect(x: 10, y: 10, width: 36, height: 36))
        box.wantsLayer = true
        box.layer?.backgroundColor = COL_HOVER.cgColor
        box.layer?.cornerRadius = 8
        let mi = NSImageView(frame: NSRect(x: 8, y: 8, width: 20, height: 20))
        mi.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)
        mi.contentTintColor = COL_PRIMARY
        box.addSubview(mi)
        m.addSubview(box)
        let mt = label(state.mediaTitle ?? "Nothing Playing", size: 12,
                       color: state.mediaTitle != nil ? COL_TEXT : COL_MUTED, weight: .semibold)
        mt.frame = NSRect(x: 56, y: 20, width: 160, height: 16)
        m.addSubview(mt)
        func mbtn(x: CGFloat, symbol: String, cmd: String) {
            let b = ClickView(frame: NSRect(x: x, y: 16, width: 24, height: 24))
            let iv = NSImageView(frame: b.bounds)
            iv.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            iv.contentTintColor = COL_TEXT
            b.addSubview(iv)
            b.onClick = { sh(BREW + cmd); DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.refreshAll() } }
            m.addSubview(b)
        }
        mbtn(x: PANEL_W - 2 * PAD - 66, symbol: state.mediaPlaying ? "pause.fill" : "play.fill", cmd: "media-control toggle-play-pause")
        mbtn(x: PANEL_W - 2 * PAD - 34, symbol: "forward.fill", cmd: "media-control next-track")
        content.addSubview(m)
        y += 56 + PAD
        return y
    }

    func renderSub(wifi: Bool) -> CGFloat {
        var y: CGFloat = PAD
        let back = card(NSRect(x: PAD, y: y, width: PANEL_W - 2 * PAD, height: 30))
        back.onClick = { [self] in view = "main"; fadeNext = true; render() }
        let bi = NSImageView(frame: NSRect(x: 10, y: 7, width: 16, height: 16))
        bi.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: nil)
        bi.contentTintColor = COL_PRIMARY
        back.addSubview(bi)
        let bl = label("Back", size: 12, color: COL_TEXT, weight: .semibold)
        bl.frame = NSRect(x: 32, y: 7, width: 100, height: 16)
        back.addSubview(bl)
        content.addSubview(back)
        y += 40

        let on = wifi ? state.wifi : state.bt
        let toggle = card(NSRect(x: PAD, y: y, width: PANEL_W - 2 * PAD, height: 44))
        let tc = circleIcon(wifi ? (on ? "wifi" : "wifi.slash") : "b.circle.fill", on: on)
        tc.setFrameOrigin(NSPoint(x: 8, y: 7))
        toggle.addSubview(tc)
        let tl = label(wifi ? "Wi-Fi" : "Bluetooth", size: 13, color: COL_TEXT, weight: .semibold)
        tl.frame = NSRect(x: 48, y: 6, width: 150, height: 16)
        toggle.addSubview(tl)
        let ts = label(on ? "On" : "Off", size: 10, color: COL_MUTED)
        ts.frame = NSRect(x: 48, y: 23, width: 150, height: 13)
        toggle.addSubview(ts)
        toggle.onClick = { [self] in
            if wifi {
                sh("networksetup -setairportpower en0 " + (state.wifi ? "off" : "on")) { _ in self.refreshAll() }
            } else {
                sh(BREW + "blueutil -p toggle") { _ in self.refreshAll() }
            }
        }
        content.addSubview(toggle)
        y += 54

        let hdr = label(wifi ? "KNOWN NETWORKS" : "DEVICES", size: 10, color: COL_MUTED, weight: .semibold)
        hdr.frame = NSRect(x: PAD + 10, y: y, width: 200, height: 14)
        content.addSubview(hdr)
        y += 20

        func choiceRow(title: String, symbol: String, tint: NSColor, trailing: String?, tap: @escaping () -> Void) {
            let r = card(NSRect(x: PAD, y: y, width: PANEL_W - 2 * PAD, height: 32))
            r.onClick = tap
            let iv = NSImageView(frame: NSRect(x: 10, y: 8, width: 16, height: 16))
            iv.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            iv.contentTintColor = tint
            r.addSubview(iv)
            let l = label(title, size: 12, color: COL_TEXT)
            l.frame = NSRect(x: 34, y: 8, width: 200, height: 16)
            r.addSubview(l)
            if let tr = trailing {
                let te = NSImageView(frame: NSRect(x: PANEL_W - 2 * PAD - 26, y: 8, width: 16, height: 16))
                te.image = NSImage(systemSymbolName: tr, accessibilityDescription: nil)
                te.contentTintColor = COL_MUTED
                r.addSubview(te)
            }
            content.addSubview(r)
            y += 38
        }

        if wifi {
            for name in state.networks {
                choiceRow(title: name, symbol: "wifi", tint: COL_MUTED, trailing: "lock.fill") { [self] in
                    sh("networksetup -setairportnetwork en0 \(shq(name))") { _ in self.refreshAll() }
                }
            }
            choiceRow(title: "Wi-Fi Settings…", symbol: "gearshape.fill", tint: COL_MUTED, trailing: nil) { [self] in
                sh("open \"x-apple.systempreferences:com.apple.wifi-settings-extension\"")
                hidePanel()
            }
        } else {
            for dev in state.devices {
                choiceRow(title: dev.name + (dev.connected ? "  ✓" : ""),
                          symbol: "b.circle.fill",
                          tint: dev.connected ? COL_TEAL : COL_MUTED,
                          trailing: nil) { [self] in
                    let action = dev.connected ? "--disconnect" : "--connect"
                    sh(BREW + "blueutil \(action) \(shq(dev.address))") { _ in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.refreshAll() }
                    }
                }
            }
            choiceRow(title: "Bluetooth Settings…", symbol: "gearshape.fill", tint: COL_MUTED, trailing: nil) { [self] in
                sh("open \"x-apple.systempreferences:com.apple.BluetoothSettings\"")
                hidePanel()
            }
        }
        y += PAD - 6
        return y
    }

    // brightness is an in-process framework call: no throttle needed, fully live
    @objc func brightnessChanged(_ s: NSSlider) {
        let v = s.integerValue
        brightnessVal = v
        _ = dsSetBrightness?(CGMainDisplayID(), Float(v) / 100.0)
    }
    @objc func volumeChanged(_ s: NSSlider) {
        let v = s.integerValue
        state.volume = v
        if abs(v - lastVolSent) >= 2 || !soundSlider.dragging {
            lastVolSent = v
            sh("osascript -e 'set volume output volume \(v)'")
        }
    }
}

// MARK: - single instance toggle via pidfile
let pidPath = "/tmp/cc_panel.pid"
let daemonStart = CommandLine.arguments.contains("--daemon")
if let old = try? String(contentsOfFile: pidPath, encoding: .utf8),
   let pid = Int32(old.trimmingCharacters(in: .whitespacesAndNewlines)),
   kill(pid, 0) == 0 {
    if daemonStart { exit(0) } // already resident: nothing to do
    kill(pid, SIGUSR1) // resident instance: toggle it, instantly
    exit(0)
}
try? String(ProcessInfo.processInfo.processIdentifier).write(toFile: pidPath, atomically: true, encoding: .utf8)

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = App()
delegate.startHidden = daemonStart
app.delegate = delegate
app.run()
