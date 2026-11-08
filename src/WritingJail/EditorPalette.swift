import AppKit

struct EditorPalette {
    let background: NSColor
    let foreground: NSColor
    let secondaryText: NSColor
    let accent: NSColor

    static let dark = EditorPalette(
        background: NSColor(calibratedWhite: 0.10, alpha: 1),
        foreground: NSColor(calibratedWhite: 0.94, alpha: 1),
        secondaryText: NSColor(calibratedWhite: 0.62, alpha: 1),
        accent: NSColor.systemTeal
    )

    static let ivory = EditorPalette(
        background: NSColor(
            calibratedRed: 0.96,
            green: 0.93,
            blue: 0.84,
            alpha: 1
        ),
        foreground: NSColor(
            calibratedRed: 0.10,
            green: 0.12,
            blue: 0.15,
            alpha: 1
        ),
        secondaryText: NSColor(
            calibratedRed: 0.40,
            green: 0.36,
            blue: 0.29,
            alpha: 1
        ),
        accent: NSColor(
            calibratedRed: 0.78,
            green: 0.30,
            blue: 0.18,
            alpha: 1
        )
    )
}
