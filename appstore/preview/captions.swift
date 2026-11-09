// captions.swift — draws the app preview's caption bars and end card as 1920x1080 PNGs, in
// the system font (SF Pro), so ffmpeg only has to overlay them. Called by make_preview.py:
//
//   swift captions.swift <out-dir> <spec.json>
//
// spec.json: {"captions": ["…", …], "endTitle": "…", "endSub": "…"}
// Writes caption00.png … (transparent, a dark bar near the bottom) and end.png (opaque).

import AppKit

let W = 1920, H = 1080
let args = CommandLine.arguments
let outDir = URL(fileURLWithPath: args[1])
struct Spec: Decodable { let captions: [String]; let endTitle: String; let endSub: String }
let spec = try! JSONDecoder().decode(Spec.self, from: Data(contentsOf: URL(fileURLWithPath: args[2])))

func image(opaque: Bool, _ draw: () -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    if opaque {
        NSColor(srgbRed: 0x0B / 255, green: 0x12 / 255, blue: 0x20 / 255, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: W, height: H).fill()
    }
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func write(_ rep: NSBitmapImageRep, _ name: String) {
    try! rep.representation(using: .png, properties: [:])!.write(to: outDir.appendingPathComponent(name))
}

func centred(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, baselineY: CGFloat) -> NSSize {
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                                .foregroundColor: color]
    let s = text as NSString
    let sz = s.size(withAttributes: attrs)
    s.draw(at: NSPoint(x: (CGFloat(W) - sz.width) / 2, y: baselineY), withAttributes: attrs)
    return sz
}

for (i, text) in spec.captions.enumerated() {
    let rep = image(opaque: false) {
        let font = NSFont.systemFont(ofSize: 54, weight: .semibold)
        let size = (text as NSString).size(withAttributes: [.font: font])
        let bar = NSRect(x: (CGFloat(W) - size.width) / 2 - 36, y: 70, width: size.width + 72, height: size.height + 36)
        NSColor.black.withAlphaComponent(0.66).setFill()
        NSBezierPath(roundedRect: bar, xRadius: 22, yRadius: 22).fill()
        _ = centred(text, size: 54, weight: .semibold, color: .white, baselineY: 88)
    }
    write(rep, String(format: "caption%02d.png", i))
}

let end = image(opaque: true) {
    _ = centred(spec.endTitle, size: 104, weight: .bold, color: .white, baselineY: CGFloat(H) / 2 + 10)
    _ = centred(spec.endSub, size: 46, weight: .medium,
                color: NSColor(srgbRed: 0x7D / 255, green: 0xD3 / 255, blue: 0xFC / 255, alpha: 1),
                baselineY: CGFloat(H) / 2 - 80)
}
write(end, "end.png")
print("captions → \(outDir.path)")
