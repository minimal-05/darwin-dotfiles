// btop-style cpu graph renderer (native replacement for cpu_graph.py:
// ~5ms per frame vs ~80ms of python+PIL startup, every provider tick)
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count >= 3 else { exit(1) }
let out = args[1]
let vals = args.dropFirst(2).compactMap { Double($0) }.map { max(0, min(100, Int($0))) }

let N = 24
let W = 80, H = 36
let cw = CGFloat(W) / CGFloat(N)

func ramp(_ v: Int) -> (CGFloat, CGFloat, CGFloat) {
    let g: (CGFloat, CGFloat, CGFloat) = (0xA8/255.0, 0xD5/255.0, 0xA2/255.0)
    let y: (CGFloat, CGFloat, CGFloat) = (0xE8/255.0, 0xC4/255.0, 0x8A/255.0)
    let r: (CGFloat, CGFloat, CGFloat) = (0xF2/255.0, 0xB8/255.0, 0xB5/255.0)
    if v <= 50 {
        let t = CGFloat(v) / 50.0
        return (g.0 + (y.0 - g.0) * t, g.1 + (y.1 - g.1) * t, g.2 + (y.2 - g.2) * t)
    }
    let t = CGFloat(v - 50) / 50.0
    return (y.0 + (r.0 - y.0) * t, y.1 + (r.1 - y.1) * t, y.2 + (r.2 - y.2) * t)
}

guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }

let tail = Array(vals.suffix(N))
for (i, v) in tail.enumerated() {
    let x0 = CGFloat(W) - CGFloat(tail.count - i) * cw
    let h = max(2, CGFloat(v) / 100.0 * CGFloat(H))
    let c = ramp(v)
    ctx.setFillColor(CGColor(red: c.0, green: c.1, blue: c.2, alpha: 0.92))
    ctx.fill(CGRect(x: x0 + 1, y: 0, width: cw - 2, height: h))
}

guard let img = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL,
                                                 UTType.png.identifier as CFString, 1, nil) else { exit(1) }
CGImageDestinationAddImage(dest, img, nil)
CGImageDestinationFinalize(dest)
print("ok")
