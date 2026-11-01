#!/usr/bin/env swift

import AppKit

let canvasSize = NSSize(width: 2_880, height: 1_800)
let outputDirectory = URL(
    fileURLWithPath: "AppStore/Screenshots/macOS",
    isDirectory: true
)
try FileManager.default.createDirectory(
    at: outputDirectory,
    withIntermediateDirectories: true
)

struct ScreenshotSpec {
    let source: String
    let output: String
    let eyebrow: String
    let title: String
    let subtitle: String
    let dark: Bool
}

let specs = [
    ScreenshotSpec(
        source: "AppStore/Screenshots/raw/editor-dark.png",
        output: "01-editor-dark.png",
        eyebrow: "DISTRACTION-FREE MARKDOWN",
        title: "Write without escape.",
        subtitle: "A focused page, a running timer, and nothing else.",
        dark: true
    ),
    ScreenshotSpec(
        source: "AppStore/Screenshots/raw/editor-ivory.png",
        output: "02-editor-ivory.png",
        eyebrow: "DARK AND IVORY",
        title: "Make the page yours.",
        subtitle: "Switch the mood without losing the words.",
        dark: false
    ),
    ScreenshotSpec(
        source: "AppStore/Screenshots/raw/file-chooser.png",
        output: "03-file-chooser.png",
        eyebrow: "START WITH A FILE",
        title: "Open. Focus. Finish.",
        subtitle: "Choose an existing draft or begin a new Markdown file.",
        dark: true
    )
]

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
    NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1)
}

func drawText(
    _ text: String,
    in rect: NSRect,
    font: NSFont,
    color: NSColor,
    alignment: NSTextAlignment = .left
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byWordWrapping
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: paragraph
    ]
    (text as NSString).draw(in: rect, withAttributes: attributes)
}

func render(_ spec: ScreenshotSpec) throws {
    guard
        let sourceImage = NSImage(contentsOfFile: spec.source),
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(canvasSize.width),
            pixelsHigh: Int(canvasSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
    else {
        throw NSError(domain: "ScreenshotRenderer", code: 1)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

    let canvas = NSRect(origin: .zero, size: canvasSize)
    let colors: [NSColor] = spec.dark
        ? [color(0.02, 0.09, 0.13), color(0.03, 0.22, 0.25)]
        : [color(0.97, 0.94, 0.85), color(0.88, 0.80, 0.65)]
    NSGradient(colors: colors)?.draw(in: canvas, angle: 315)

    let glowColor = spec.dark
        ? color(0.08, 0.74, 0.64).withAlphaComponent(0.12)
        : color(1.0, 0.41, 0.27).withAlphaComponent(0.11)
    glowColor.setFill()
    NSBezierPath(
        ovalIn: NSRect(x: 1_980, y: 1_110, width: 1_160, height: 1_160)
    ).fill()
    NSBezierPath(
        ovalIn: NSRect(x: -310, y: -420, width: 900, height: 900)
    ).fill()

    let foreground = spec.dark
        ? color(0.96, 0.95, 0.90)
        : color(0.10, 0.12, 0.15)
    let secondary = spec.dark
        ? color(0.52, 0.72, 0.70)
        : color(0.40, 0.35, 0.27)
    let accent = spec.dark
        ? color(0.13, 0.86, 0.72)
        : color(0.82, 0.30, 0.18)

    drawText(
        spec.eyebrow,
        in: NSRect(x: 150, y: 1_682, width: 2_580, height: 36),
        font: .monospacedSystemFont(ofSize: 25, weight: .bold),
        color: accent
    )
    drawText(
        spec.title,
        in: NSRect(x: 150, y: 1_535, width: 2_580, height: 118),
        font: .systemFont(ofSize: 82, weight: .bold),
        color: foreground
    )
    drawText(
        spec.subtitle,
        in: NSRect(x: 150, y: 1_465, width: 2_500, height: 54),
        font: .systemFont(ofSize: 30, weight: .regular),
        color: secondary
    )

    let maxImageSize = NSSize(width: 1_900, height: 1_300)
    let scale = min(
        maxImageSize.width / sourceImage.size.width,
        maxImageSize.height / sourceImage.size.height
    )
    let imageSize = NSSize(
        width: sourceImage.size.width * scale,
        height: sourceImage.size.height * scale
    )
    let imageRect = NSRect(
        x: (canvasSize.width - imageSize.width) / 2,
        y: 92,
        width: imageSize.width,
        height: imageSize.height
    )

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.32)
    shadow.shadowBlurRadius = 34
    shadow.shadowOffset = NSSize(width: 0, height: -14)
    shadow.set()
    sourceImage.draw(
        in: imageRect,
        from: .zero,
        operation: .sourceOver,
        fraction: 1
    )
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "ScreenshotRenderer", code: 2)
    }
    try data.write(to: outputDirectory.appendingPathComponent(spec.output))
}

for spec in specs {
    try render(spec)
    print("Rendered \(spec.output)")
}
