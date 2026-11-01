#!/usr/bin/env swift

import AppKit

let canvasSize = 1_024
let outputPath = CommandLine.arguments.dropFirst().first
    ?? "assets/AppIcon-1024.png"

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: canvasSize,
    pixelsHigh: canvasSize,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fatalError("Unable to create icon bitmap")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
guard let context = NSGraphicsContext.current?.cgContext else {
    fatalError("Unable to create icon graphics context")
}

context.clear(CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize))
context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)

let backgroundRect = CGRect(x: 92, y: 92, width: 840, height: 840)
let backgroundPath = CGPath(
    roundedRect: backgroundRect,
    cornerWidth: 192,
    cornerHeight: 192,
    transform: nil
)

context.saveGState()
context.setShadow(
    offset: CGSize(width: 0, height: -18),
    blur: 34,
    color: NSColor.black.withAlphaComponent(0.32).cgColor
)
context.addPath(backgroundPath)
context.setFillColor(NSColor(calibratedWhite: 0.04, alpha: 1).cgColor)
context.fillPath()
context.restoreGState()

context.saveGState()
context.addPath(backgroundPath)
context.clip()

let backgroundGradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        NSColor(calibratedRed: 0.05, green: 0.69, blue: 0.62, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.04, green: 0.17, blue: 0.27, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.035, green: 0.055, blue: 0.13, alpha: 1).cgColor
    ] as CFArray,
    locations: [0.0, 0.54, 1.0]
)!
context.drawLinearGradient(
    backgroundGradient,
    start: CGPoint(x: 160, y: 900),
    end: CGPoint(x: 870, y: 110),
    options: []
)

context.setStrokeColor(NSColor.white.withAlphaComponent(0.08).cgColor)
context.setLineWidth(3)
for offset in stride(from: CGFloat(0), through: 420, by: 62) {
    context.strokeEllipse(
        in: CGRect(
            x: 540 - offset,
            y: 790 - offset,
            width: 420 + offset * 2,
            height: 420 + offset * 2
        )
    )
}

context.setFillColor(NSColor.white.withAlphaComponent(0.035).cgColor)
context.fillEllipse(in: CGRect(x: 690, y: 690, width: 250, height: 250))
context.restoreGState()

context.setStrokeColor(NSColor.white.withAlphaComponent(0.16).cgColor)
context.setLineWidth(3)
context.addPath(backgroundPath)
context.strokePath()

let ivory = NSColor(calibratedRed: 0.98, green: 0.95, blue: 0.86, alpha: 1)
let mint = NSColor(calibratedRed: 0.12, green: 0.82, blue: 0.70, alpha: 1)
let ink = NSColor(calibratedRed: 0.025, green: 0.055, blue: 0.11, alpha: 1)
let coral = NSColor(calibratedRed: 1.0, green: 0.40, blue: 0.27, alpha: 1)

context.saveGState()
context.setShadow(
    offset: CGSize(width: 0, height: -10),
    blur: 22,
    color: NSColor.black.withAlphaComponent(0.34).cgColor
)
context.setStrokeColor(ivory.cgColor)
context.setLineWidth(108)
context.setLineCap(.round)
context.setLineJoin(.round)
context.move(to: CGPoint(x: 270, y: 684))
context.addLine(to: CGPoint(x: 350, y: 344))
context.addLine(to: CGPoint(x: 510, y: 606))
context.addLine(to: CGPoint(x: 670, y: 344))
context.addLine(to: CGPoint(x: 750, y: 684))
context.strokePath()
context.restoreGState()

context.setStrokeColor(mint.withAlphaComponent(0.92).cgColor)
context.setLineWidth(26)
context.setLineJoin(.round)
context.addPath(
    CGPath(
        roundedRect: CGRect(x: 208, y: 176, width: 608, height: 672),
        cornerWidth: 62,
        cornerHeight: 62,
        transform: nil
    )
)
context.strokePath()

for barX in [CGFloat(348), 448, 576, 676] {
    let bar = CGPath(
        roundedRect: CGRect(x: barX, y: 196, width: 30, height: 632),
        cornerWidth: 15,
        cornerHeight: 15,
        transform: nil
    )
    context.saveGState()
    context.setShadow(
        offset: .zero,
        blur: 10,
        color: mint.withAlphaComponent(0.24).cgColor
    )
    context.addPath(bar)
    context.setFillColor(ink.withAlphaComponent(0.92).cgColor)
    context.fillPath()
    context.restoreGState()
}

context.setFillColor(coral.cgColor)
context.fillEllipse(in: CGRect(x: 491, y: 794, width: 42, height: 42))

NSGraphicsContext.restoreGraphicsState()

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Unable to encode icon PNG")
}

let outputURL = URL(fileURLWithPath: outputPath)
try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try pngData.write(to: outputURL, options: .atomic)
print("Generated \(outputURL.path)")
