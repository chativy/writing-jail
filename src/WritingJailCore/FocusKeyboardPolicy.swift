import CoreGraphics
import Foundation

public enum FocusKeyboardPolicy {
    public static let emergencyHoldSeconds: TimeInterval = 5
    public static let systemDefinedCGEventType: CGEventType = .init(rawValue: 14)!

    // Copy, paste, cut, select all, undo/redo, and zoom remain available.
    private static let allowedCommandKeyCodes: Set<CGKeyCode> = [
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

    private static let blockedFunctionKeyCodes: Set<CGKeyCode> = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111
    ]

    public static func shouldBlockKeyboardEvent(
        type: CGEventType,
        keyCode: CGKeyCode,
        flags: CGEventFlags
    ) -> Bool {
        if type == systemDefinedCGEventType {
            return true
        }
        guard type == .keyDown else {
            return false
        }

        if flags.contains(.maskCommand) {
            return !allowedCommandKeyCodes.contains(keyCode)
        }

        let controlArrow = flags.contains(.maskControl) && (123...126).contains(keyCode)
        return controlArrow || blockedFunctionKeyCodes.contains(keyCode)
    }

    public static func isEmergencyExitChord(
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
