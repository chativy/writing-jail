import AppKit
import ApplicationServices
import CoreGraphics
import WritingJailCore

@MainActor
final class FocusKeyboardBlocker {
    var onEmergencyExit: (() -> Void)?

    private var keyboardEventTap: CFMachPort?
    private var keyboardEventTapSource: CFRunLoopSource?
    private var emergencyExitWorkItem: DispatchWorkItem?

    var isBlocking: Bool {
        keyboardEventTap != nil
    }

    static var accessibilityAccessGranted: Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibilityAccess() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilityPrivacySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @discardableResult
    func startBlocking() -> Bool {
        stopBlocking()
        guard Self.accessibilityAccessGranted else {
            return false
        }

        let mask =
            (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
            | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
            | (CGEventMask(1) << FocusKeyboardPolicy.systemDefinedCGEventType.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.keyboardEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        keyboardEventTap = tap
        keyboardEventTapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let keyboardEventTapSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), keyboardEventTapSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stopBlocking() {
        emergencyExitWorkItem?.cancel()
        emergencyExitWorkItem = nil

        if let keyboardEventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), keyboardEventTapSource, .commonModes)
        }
        if let keyboardEventTap {
            CGEvent.tapEnable(tap: keyboardEventTap, enable: false)
            CFMachPortInvalidate(keyboardEventTap)
        }
        keyboardEventTapSource = nil
        keyboardEventTap = nil
    }

    fileprivate func scheduleEmergencyExit() {
        guard emergencyExitWorkItem == nil else {
            return
        }

        let item = DispatchWorkItem { [weak self] in
            guard let self, self.emergencyExitWorkItem?.isCancelled == false else {
                return
            }
            self.emergencyExitWorkItem = nil
            self.onEmergencyExit?()
        }
        emergencyExitWorkItem = item
        DispatchQueue.main.asyncAfter(
            deadline: .now() + FocusKeyboardPolicyAdapter.emergencyHoldSeconds,
            execute: item
        )
    }

    fileprivate func cancelEmergencyExit() {
        emergencyExitWorkItem?.cancel()
        emergencyExitWorkItem = nil
    }

    fileprivate func reenableEventTap() {
        guard let keyboardEventTap else {
            return
        }
        CGEvent.tapEnable(tap: keyboardEventTap, enable: true)
    }

    private static let keyboardEventTapCallback: CGEventTapCallBack = {
        proxy,
        type,
        event,
        userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let blocker = Unmanaged<FocusKeyboardBlocker>
            .fromOpaque(userInfo)
            .takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            DispatchQueue.main.async {
                blocker.reenableEventTap()
            }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = CGKeyCode(
            event.getIntegerValueField(.keyboardEventKeycode)
        )
        let flags = event.flags

        if FocusKeyboardPolicyAdapter.isEmergencyExitChord(
            type: type,
            keyCode: keyCode,
            flags: flags
        ) {
            DispatchQueue.main.async {
                blocker.scheduleEmergencyExit()
            }
            return nil
        }

        if type == .keyUp && keyCode == 53 {
            DispatchQueue.main.async {
                blocker.cancelEmergencyExit()
            }
        } else if type == .flagsChanged
            && !(flags.contains(.maskControl) && flags.contains(.maskAlternate)) {
            DispatchQueue.main.async {
                blocker.cancelEmergencyExit()
            }
        }

        if FocusKeyboardPolicyAdapter.shouldBlockKeyboardEvent(
            type: type,
            keyCode: keyCode,
            flags: flags
        ) {
            return nil
        }
        return Unmanaged.passUnretained(event)
    }
}

private enum FocusKeyboardPolicyAdapter {
    static let emergencyHoldSeconds = FocusKeyboardPolicy.emergencyHoldSeconds

    static func shouldBlockKeyboardEvent(
        type: CGEventType,
        keyCode: CGKeyCode,
        flags: CGEventFlags
    ) -> Bool {
        FocusKeyboardPolicy.shouldBlockKeyboardEvent(
            type: type,
            keyCode: keyCode,
            flags: flags
        )
    }

    static func isEmergencyExitChord(
        type: CGEventType,
        keyCode: CGKeyCode,
        flags: CGEventFlags
    ) -> Bool {
        FocusKeyboardPolicy.isEmergencyExitChord(
            type: type,
            keyCode: keyCode,
            flags: flags
        )
    }
}
