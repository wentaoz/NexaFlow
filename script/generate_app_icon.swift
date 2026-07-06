#!/usr/bin/env swift

import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resources = root.appendingPathComponent("Resources", isDirectory: true)
let iconset = resources.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let bounds = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    bounds.fill()

    let radius = size * 0.215
    let appShape = NSBezierPath(roundedRect: bounds.insetBy(dx: size * 0.035, dy: size * 0.035), xRadius: radius, yRadius: radius)

    guard let baseGradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.035, green: 0.18, blue: 0.30, alpha: 1),
        NSColor(calibratedRed: 0.02, green: 0.36, blue: 0.50, alpha: 1),
        NSColor(calibratedRed: 0.02, green: 0.50, blue: 0.40, alpha: 1)
    ]) else {
        fatalError("Unable to create gradient with valid colors")
    }
    baseGradient.draw(in: appShape, angle: -38)

    NSColor(calibratedWhite: 1, alpha: 0.14).setStroke()
    appShape.lineWidth = max(1, size * 0.012)
    appShape.stroke()

    let center = NSPoint(x: size * 0.50, y: size * 0.51)
    let radarRadius = size * 0.31
    for scale in [0.40, 0.70, 1.0] {
        let ring = NSBezierPath(ovalIn: NSRect(
            x: center.x - radarRadius * scale,
            y: center.y - radarRadius * scale,
            width: radarRadius * 2 * scale,
            height: radarRadius * 2 * scale
        ))
        NSColor(calibratedRed: 0.70, green: 0.98, blue: 0.92, alpha: 0.23).setStroke()
        ring.lineWidth = max(1.2, size * 0.007)
        ring.stroke()
    }

    let crosshair = NSBezierPath()
    crosshair.move(to: NSPoint(x: center.x - radarRadius, y: center.y))
    crosshair.line(to: NSPoint(x: center.x + radarRadius, y: center.y))
    crosshair.move(to: NSPoint(x: center.x, y: center.y - radarRadius))
    crosshair.line(to: NSPoint(x: center.x, y: center.y + radarRadius))
    NSColor(calibratedRed: 0.70, green: 0.98, blue: 0.92, alpha: 0.18).setStroke()
    crosshair.lineWidth = max(1, size * 0.006)
    crosshair.stroke()

    let sweep = NSBezierPath()
    sweep.move(to: center)
    sweep.line(to: NSPoint(x: size * 0.77, y: size * 0.70))
    sweep.lineWidth = max(3, size * 0.022)
    sweep.lineCapStyle = .round
    NSColor(calibratedRed: 0.82, green: 1.0, blue: 0.88, alpha: 0.85).setStroke()
    sweep.stroke()

    let chart = NSBezierPath()
    let points = [
        NSPoint(x: size * 0.25, y: size * 0.38),
        NSPoint(x: size * 0.38, y: size * 0.47),
        NSPoint(x: size * 0.49, y: size * 0.43),
        NSPoint(x: size * 0.62, y: size * 0.60),
        NSPoint(x: size * 0.76, y: size * 0.66)
    ]
    chart.move(to: points[0])
    for point in points.dropFirst() {
        chart.line(to: point)
    }
    chart.lineWidth = max(5, size * 0.034)
    chart.lineCapStyle = .round
    chart.lineJoinStyle = .round
    NSColor(calibratedRed: 1.0, green: 0.82, blue: 0.28, alpha: 0.98).setStroke()
    chart.stroke()

    for point in points {
        let dotRect = NSRect(x: point.x - size * 0.024, y: point.y - size * 0.024, width: size * 0.048, height: size * 0.048)
        NSColor(calibratedRed: 1.0, green: 0.93, blue: 0.57, alpha: 1).setFill()
        NSBezierPath(ovalIn: dotRect).fill()
        NSColor(calibratedRed: 0.04, green: 0.20, blue: 0.28, alpha: 0.55).setStroke()
        let outline = NSBezierPath(ovalIn: dotRect)
        outline.lineWidth = max(1, size * 0.006)
        outline.stroke()
    }

    let aiNodeRect = NSRect(x: size * 0.34, y: size * 0.68, width: size * 0.32, height: size * 0.14)
    let aiNode = NSBezierPath(roundedRect: aiNodeRect, xRadius: size * 0.04, yRadius: size * 0.04)
    NSColor(calibratedWhite: 1, alpha: 0.18).setFill()
    aiNode.fill()
    NSColor(calibratedRed: 0.76, green: 1.0, blue: 0.95, alpha: 0.62).setStroke()
    aiNode.lineWidth = max(1, size * 0.006)
    aiNode.stroke()

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let font = NSFont.systemFont(ofSize: size * 0.075, weight: .heavy)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.96),
        .paragraphStyle: paragraph,
        .kern: 0
    ]
    NSString(string: "AI").draw(in: aiNodeRect.insetBy(dx: 0, dy: size * 0.018), withAttributes: attrs)

    let shadowPath = NSBezierPath(roundedRect: bounds.insetBy(dx: size * 0.05, dy: size * 0.05), xRadius: radius, yRadius: radius)
    NSColor(calibratedWhite: 0, alpha: 0.18).setStroke()
    shadowPath.lineWidth = max(2, size * 0.018)
    shadowPath.stroke()

    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, to url: URL, pixels: Int) throws {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "IconGeneration", code: 1)
    }
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "IconGeneration", code: 2)
    }
    try data.write(to: url)
}

let specs: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for spec in specs {
    let image = drawIcon(size: CGFloat(spec.pixels))
    try writePNG(image, to: iconset.appendingPathComponent(spec.name), pixels: spec.pixels)
}

let preview = drawIcon(size: 1024)
try writePNG(preview, to: resources.appendingPathComponent("AppIcon-preview.png"), pixels: 1024)

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = [
    "-c", "icns",
    iconset.path,
    "-o", resources.appendingPathComponent("AppIcon.icns").path
]
try process.run()
process.waitUntilExit()
if process.terminationStatus != 0 {
    throw NSError(domain: "IconGeneration", code: Int(process.terminationStatus))
}
