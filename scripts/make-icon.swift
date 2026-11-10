// Draws the CW Notebook app icon and writes Resources/AppIcon.icns.
// Run from the project root:  swift scripts/make-icon.swift
import AppKit

let size: CGFloat = 1024

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

func drawIcon(in ctx: CGContext) {
    // macOS icon grid: an 824pt rounded tile centred on the 1024 canvas.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
    ctx.addPath(tilePath)
    ctx.setFillColor(color(0x1E2B4A))
    ctx.fillPath()
    ctx.restoreGState()

    // Deep blue tile with a soft top-to-bottom gradient.
    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                              colors: [color(0x34508A), color(0x1B2742)] as CFArray,
                              locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY), options: [])
    ctx.restoreGState()

    // The notepad page.
    let page = CGRect(x: 232, y: 178, width: 560, height: 640)
    let pagePath = CGPath(roundedRect: page, cornerWidth: 34, cornerHeight: 34, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, 0.4))
    ctx.addPath(pagePath)
    ctx.setFillColor(color(0xFBF8F1))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(pagePath)
    ctx.clip()

    // Binding strip across the top.
    let band = CGRect(x: page.minX, y: page.maxY - 104, width: page.width, height: 104)
    ctx.setFillColor(color(0xD9534A))
    ctx.fill(band)

    // Ruled lines and margin.
    ctx.setStrokeColor(color(0x9DB7D9))
    ctx.setLineWidth(5)
    var y = band.minY - 92
    while y > page.minY + 40 {
        ctx.move(to: CGPoint(x: page.minX, y: y))
        ctx.addLine(to: CGPoint(x: page.maxX, y: y))
        y -= 84
    }
    ctx.strokePath()
    ctx.setStrokeColor(color(0xE7A39E))
    ctx.setLineWidth(5)
    ctx.move(to: CGPoint(x: page.minX + 92, y: page.minY))
    ctx.addLine(to: CGPoint(x: page.minX + 92, y: band.minY))
    ctx.strokePath()
    ctx.restoreGState()

    // Binding rings.
    for i in 0..<5 {
        let x = page.minX + 88 + CGFloat(i) * 96
        let ring = CGRect(x: x - 18, y: band.maxY - 42, width: 36, height: 80)
        ctx.setFillColor(color(0xC9CED6))
        ctx.addPath(CGPath(roundedRect: ring, cornerWidth: 18, cornerHeight: 18, transform: nil))
        ctx.fillPath()
        ctx.setFillColor(color(0x8A3A33))
        ctx.fillEllipse(in: CGRect(x: x - 12, y: band.maxY - 56, width: 24, height: 24))
    }

    // "CW" written in dits and dahs on the ruled lines: −·−·  ·−−
    let ink = color(0x1E2B4A)
    ctx.setFillColor(ink)
    let unit: CGFloat = 30
    func drawCode(_ code: String, startX: CGFloat, baseline: CGFloat) {
        var x = startX
        for el in code {
            let w = el == "-" ? unit * 3 : unit
            let r = CGRect(x: x, y: baseline + 14, width: w, height: unit)
            ctx.addPath(CGPath(roundedRect: r, cornerWidth: unit / 2, cornerHeight: unit / 2, transform: nil))
            ctx.fillPath()
            x += w + unit
        }
    }
    let line1 = band.minY - 92 - 84      // second ruled line
    drawCode("-.-.", startX: page.minX + 130, baseline: line1)
    drawCode(".--", startX: page.minX + 130, baseline: line1 - 84)

    // A pencil-short third line, as if the note is still being written.
    ctx.setFillColor(color(0x1E2B4A, 0.28))
    ctx.addPath(CGPath(roundedRect: CGRect(x: page.minX + 130, y: line1 - 168 + 14, width: 210, height: unit),
                       cornerWidth: unit / 2, cornerHeight: unit / 2, transform: nil))
    ctx.fillPath()
}

func png(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let gc = NSGraphicsContext(bitmapImageRep: rep)!
    let ctx = gc.cgContext
    ctx.scaleBy(x: CGFloat(pixels) / size, y: CGFloat(pixels) / size)
    drawIcon(in: ctx)
    gc.flushGraphics()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! png(pixels: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! png(pixels: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try! png(pixels: 1024).write(to: URL(fileURLWithPath: "Resources/AppIcon-1024.png"))

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try! task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
