//
//  Render.swift — Mac App Store screenshots for Mission Control.
//
//  Renders the app's real SwiftUI views (compiled in from the app target) at 4x, then
//  composes each shot from shots-mac.json onto a 2880×1800 canvas: caption on the left,
//  the panel on the right. Run via ../render-mac.sh.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Spec

struct Spec: Codable {
    struct Canvas: Codable { let width: Int; let height: Int }
    struct Theme: Codable {
        let background: [String]
        let glow: String
        let captionColor: String
        let accent: String
        let subColor: String
    }
    struct Crop: Codable { let x: Double; let y: Double; let w: Double; let h: Double }
    struct Shot: Codable {
        let id: String
        let caption: String
        let subcaption: String?
        let source: String
        let crop: Crop?
        let fit: String?
        /// "top": caption across the top, the image full width below (for whole-screen
        /// captures). Otherwise caption on the left, image on the right.
        let layout: String?
    }
    let app: String
    let canvas: Canvas
    let theme: Theme
    let raw: String
    let output: String
    let shots: [Shot]
}

// MARK: - No-op actions for rendering

@MainActor
final class RenderActions: PopoverActions {
    func openSettings() {}
    func requestAccessibility() {}
    func triggerMissionControl() {}
    func triggerAppLauncher() {}
    func triggerAppExpose() {}
    func triggerShowDesktop() {}
    func triggerPreviousSpace() {}
    func triggerNextSpace() {}
    func triggerSpotlight() {}
    func triggerScreenshot() {}
    func focusApp(_ app: NSRunningApplication) {}
    func quitApp(_ app: NSRunningApplication) {}
    func nameThisSpace() {}
}

// MARK: - Helpers

func fail(_ message: String) -> Never {
    FileManager.default.changeCurrentDirectoryPath("/")
    fputs("error: \(message)\n", stderr)
    exit(1)
}

extension NSColor {
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard let v = UInt64(s, radix: 16) else { fail("bad color \(hex)") }
        let hasAlpha = s.count == 8
        let r = CGFloat((v >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let g = CGFloat((v >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let b = CGFloat((v >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let a = hasAlpha ? CGFloat(v & 0xFF) / 255 : 1
        self.init(srgbRed: r, green: g, blue: b, alpha: a)
    }
}

func writePNG(_ image: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fail("can't create \(url.path)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fail("can't write \(url.path)") }
}

func loadImage(_ url: URL) -> CGImage {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { fail("can't read \(url.path)") }
    return img
}

/// "Mission Control, **one click away**" → attributed string with the accent phrase colored.
func caption(_ text: String, font: NSFont, color: NSColor, accent: NSColor) -> NSAttributedString {
    let result = NSMutableAttributedString()
    var accented = false
    for (i, part) in text.components(separatedBy: "**").enumerated() {
        accented = i % 2 == 1
        result.append(NSAttributedString(string: part, attributes: [
            .font: font,
            .foregroundColor: accented ? accent : color,
        ]))
    }
    return result
}

// MARK: - Rendering the app's views

/// Snapshots the view through a real (offscreen) window so AppKit-backed controls —
/// text fields, scroll views, forms — render as they do in the app. `ImageRenderer`
/// skips those on macOS. Always dark appearance, matching the store background.
@MainActor
func renderView<V: View>(_ view: V, scale: CGFloat) -> CGImage {
    let appearance = NSAppearance(named: .darkAqua)
    let hosting = NSHostingView(rootView: view)
    hosting.appearance = appearance
    let size = hosting.fittingSize
    hosting.frame = CGRect(origin: .zero, size: size)

    let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = appearance
    window.isReleasedWhenClosed = false
    window.contentView = hosting
    // Off screen, but ordered in so layout and image loading actually happen.
    window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
    window.orderFrontRegardless()
    hosting.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.5))

    let pixelW = Int(size.width * scale), pixelH = Int(size.height * scale)
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelW, pixelsHigh: pixelH,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
        fail("can't allocate bitmap")
    }
    rep.size = size
    hosting.cacheDisplay(in: hosting.bounds, to: rep)
    window.orderOut(nil)
    guard let image = rep.cgImage else { fail("snapshot failed") }
    return image
}

@MainActor
func renderRaws(into dir: URL, scale: CGFloat) {
    let actions = RenderActions()
    let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }

    let frontmost = apps.sorted {
        ($0.localizedName ?? "").localizedCaseInsensitiveCompare($1.localizedName ?? "") == .orderedAscending
    }.first
    let panel = MainPopoverView(actions: actions, frontmostApp: frontmost, hasAccessibility: true,
                                spaceName: "Research")
    writePNG(renderView(panel, scale: scale), to: dir.appendingPathComponent("panel.png"))

    writePNG(renderView(SettingsView(), scale: scale), to: dir.appendingPathComponent("settings.png"))
    print("rendered raws → \(dir.path)")
}

// MARK: - Composing a shot

func compose(_ shot: Spec.Shot, spec: Spec, rawDir: URL) -> CGImage {
    let W = CGFloat(spec.canvas.width), H = CGFloat(spec.canvas.height)
    let theme = spec.theme

    guard let ctx = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fail("no context") }
    ctx.interpolationQuality = .high

    // Background gradient (top-left → bottom-right) and a soft glow behind the panel.
    let colors = theme.background.map { NSColor(hex: $0).cgColor } as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: nil)!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: H), end: CGPoint(x: W, y: 0), options: [])

    let glowColor = NSColor(hex: theme.glow)
    let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                          colors: [glowColor.withAlphaComponent(0.28).cgColor, glowColor.withAlphaComponent(0).cgColor] as CFArray,
                          locations: [0, 1])!
    let top = shot.layout == "top"
    let glowCenter = top ? CGPoint(x: W * 0.5, y: H * 0.38) : CGPoint(x: W * 0.72, y: H * 0.5)
    ctx.drawRadialGradient(glow, startCenter: glowCenter, startRadius: 0, endCenter: glowCenter, endRadius: H * 0.62, options: [])

    // Panel image (optionally cropped), fitted into the right-hand box.
    var image = loadImage(rawDir.appendingPathComponent(shot.source))
    if let c = shot.crop {
        let rect = CGRect(x: CGFloat(image.width) * c.x, y: CGFloat(image.height) * c.y,
                          width: CGFloat(image.width) * c.w, height: CGFloat(image.height) * c.h).integral
        guard let cropped = image.cropping(to: rect) else { fail("crop failed for \(shot.id)") }
        image = cropped
    }
    let box = top ? CGRect(x: W * 0.06, y: H * 0.04, width: W * 0.88, height: H * 0.72)
                  : CGRect(x: W * 0.50, y: H * 0.08, width: W * 0.44, height: H * 0.84)
    let imageSize = CGSize(width: image.width, height: image.height)
    var scale = min(box.width / imageSize.width, box.height / imageSize.height)
    if shot.fit == "width" { scale = box.width / imageSize.width }
    // Never enlarge a crop past 1.15× its 4x render, so nothing goes soft.
    scale = min(scale, 1.15)
    let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    let drawRect = CGRect(x: box.midX - drawSize.width / 2, y: box.midY - drawSize.height / 2,
                          width: drawSize.width, height: drawSize.height).integral
    let radius: CGFloat = top ? 22 : 34

    // Shadow, then the clipped image, then a hairline so the card reads against the background.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -28), blur: 90, color: NSColor.black.withAlphaComponent(0.55).cgColor)
    ctx.setFillColor(NSColor(hex: "#1E1E1E").cgColor)
    ctx.addPath(CGPath(roundedRect: drawRect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: drawRect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.clip()
    ctx.draw(image, in: drawRect)
    ctx.restoreGState()

    ctx.saveGState()
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.14).cgColor)
    ctx.setLineWidth(3)
    ctx.addPath(CGPath(roundedRect: drawRect.insetBy(dx: 1.5, dy: 1.5), cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.strokePath()
    ctx.restoreGState()

    // Captions, left column, vertically centred.
    let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ns

    // Side layout: a left column, vertically centred. Top layout: a centred band above the
    // image, one or two lines each.
    let column = top ? CGRect(x: W * 0.06, y: box.maxY, width: W * 0.88, height: H - box.maxY)
                     : CGRect(x: W * 0.065, y: 0, width: W * 0.40, height: H)
    let titleFont = NSFont.systemFont(ofSize: top ? 92 : 116, weight: .bold)
    let subFont = NSFont.systemFont(ofSize: top ? 40 : 46, weight: .regular)
    let title = NSMutableAttributedString(attributedString: caption(shot.caption, font: titleFont,
        color: NSColor(hex: theme.captionColor), accent: NSColor(hex: theme.accent)))
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = top ? .center : .natural
    title.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: title.length))
    let sub = shot.subcaption.map {
        NSAttributedString(string: $0, attributes: [.font: subFont, .foregroundColor: NSColor(hex: theme.subColor),
                                                    .paragraphStyle: paragraph])
    }
    let options: NSString.DrawingOptions = [.usesLineFragmentOrigin]
    let titleSize = title.boundingRect(with: CGSize(width: column.width, height: H), options: options).size
    let subSize = sub?.boundingRect(with: CGSize(width: column.width, height: H), options: options).size ?? .zero
    let gap: CGFloat = sub == nil ? 0 : (top ? 18 : 44)
    let total = titleSize.height + gap + subSize.height
    var y = column.midY + total / 2   // top of the block, in the unflipped coordinate system
    title.draw(with: CGRect(x: column.minX, y: y - titleSize.height, width: column.width, height: titleSize.height), options: options)
    y -= titleSize.height + gap
    sub?.draw(with: CGRect(x: column.minX, y: y - subSize.height, width: column.width, height: subSize.height), options: options)

    NSGraphicsContext.restoreGraphicsState()

    guard let result = ctx.makeImage() else { fail("makeImage failed") }
    return result
}

func contactSheet(_ images: [CGImage], to url: URL) {
    guard let first = images.first else { return }
    let thumbW = 960, thumbH = thumbW * first.height / first.width, gap = 24
    let cols = 2, rows = (images.count + cols - 1) / cols
    let W = cols * thumbW + (cols + 1) * gap, H = rows * thumbH + (rows + 1) * gap
    guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fail("no context") }
    ctx.setFillColor(NSColor(hex: "#444444").cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    ctx.interpolationQuality = .high
    for (i, img) in images.enumerated() {
        let col = i % cols, row = i / cols
        let x = gap + col * (thumbW + gap)
        let y = H - (gap + (row + 1) * thumbH + row * gap)
        ctx.draw(img, in: CGRect(x: x, y: y, width: thumbW, height: thumbH))
    }
    writePNG(ctx.makeImage()!, to: url)
}

// MARK: - Main

@main
@MainActor
struct Render {
    static func main() throws {
        let args = CommandLine.arguments
        guard args.count >= 2 else { fail("usage: render <shots-mac.json> [--skip-raws]") }
        let specURL = URL(fileURLWithPath: args[1])
        let base = specURL.deletingLastPathComponent()
        let spec = try JSONDecoder().decode(Spec.self, from: Data(contentsOf: specURL))
        let rawDir = base.appendingPathComponent(spec.raw)
        let outDir = base.appendingPathComponent(spec.output)
        try FileManager.default.createDirectory(at: rawDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)

        if !args.contains("--skip-raws") {
            renderRaws(into: rawDir, scale: 4)
        }

        var rendered: [CGImage] = []
        for (i, shot) in spec.shots.enumerated() {
            let image = compose(shot, spec: spec, rawDir: rawDir)
            let name = String(format: "%02d-%@.png", i + 1, shot.id)
            writePNG(image, to: outDir.appendingPathComponent(name))
            rendered.append(image)
            print("wrote \(spec.output)/\(name)  \(image.width)×\(image.height)")
        }
        contactSheet(rendered, to: outDir.appendingPathComponent("contact-sheet.png"))
        print("contact sheet → \(spec.output)/contact-sheet.png")
    }
}
