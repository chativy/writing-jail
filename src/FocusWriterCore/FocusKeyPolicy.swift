import CoreGraphics
import Foundation

public enum FocusKeyPolicy {
    public static let emergencyHoldSeconds: TimeInterval = 5
    public static let systemDefinedEventType: CGEventType = .init(rawValue: 14)!

    // Copy, paste, cut, select all, undo/redo, and zoom remain available.
    private static let allowedCommandKeys: Set<CGKeyCode> = [
        0,   // A
        6,   // Z
        7,   // X
        8,   // C
        9,   // V
        24,  // = / +
        27,  // -
        69,  // keypad +
        78   // keypad -
    ]

    private static let functionKeys: Set<CGKeyCode> = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111
    ]

    public static func shouldBlock(
        type: CGEventType,
        keyCode: CGKeyCode,
        flags: CGEventFlags
    ) -> Bool {
        if type == systemDefinedEventType {
            return true
        }
        guard type == .keyDown else {
            return false
        }

        if flags.contains(.maskCommand) {
            return !allowedCommandKeys.contains(keyCode)
        }

        let controlArrow = flags.contains(.maskControl) && (123...126).contains(keyCode)
        return controlArrow || functionKeys.contains(keyCode)
    }

    public static func isEmergencyChord(
        type: CGEventType,
        keyCode: CGKeyCode,
        flags: CGEventFlags
    ) -> Bool {
        guard type == .keyDown, keyCode == 53 else {
            return false
        }
        return flags.contains(.maskControl) && flags.contains(.maskAlternate)
    }
}
