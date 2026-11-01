import AppKit
import ApplicationServices
import CoreGraphics
import FocusWriterCore

@MainActor
final class FocusInputBlocker {
    var onEmergencyUnlock: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var emergencyWorkItem: DispatchWorkItem?

    var isRunning: Bool {
        eventTap != nil
    }

    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibilityPermission() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @discardableResult
    func start() -> Bool {
        stop()
        guard Self.hasAccessibilityPermission else {
            return false
        }

        let mask =
            (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
            | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
            | (CGEventMask(1) << FocusKeyPolicy.systemDefinedEventType.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        emergencyWorkItem?.cancel()
        emergencyWorkItem = nil

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        runLoopSource = nil
        eventTap = nil
    }

    fileprivate func armEmergencyUnlock() {
        guard emergencyWorkItem == nil else {
            return
        }

        let item = DispatchWorkItem { [weak self] in
            guard let self, self.emergencyWorkItem?.isCancelled == false else {
                return
            }
            self.emergencyWorkItem = nil
            self.onEmergencyUnlock?()
        }
        emergencyWorkItem = item
        DispatchQueue.main.asyncAfter(
            deadline: .now() + FocusKeyPolicyBridge.emergencyHoldSeconds,
            execute: item
        )
    }

    fileprivate func cancelEmergencyUnlock() {
        emergencyWorkItem?.cancel()
        emergencyWorkItem = nil
    }

    fileprivate func reenableAfterSystemDisable() {
        guard let eventTap else {
            return
        }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private static let eventTapCallback: CGEventTapCallBack = {
        proxy,
        type,
        event,
        userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let blocker = Unmanaged<FocusInputBlocker>
            .fromOpaque(userInfo)
            .takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            DispatchQueue.main.async {
                blocker.reenableAfterSystemDisable()
            }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = CGKeyCode(
            event.getIntegerValueField(.keyboardEventKeycode)
        )
        let flags = event.flags

        if FocusKeyPolicyBridge.isEmergencyChord(
            type: type,
            keyCode: keyCode,
            flags: flags
        ) {
            DispatchQueue.main.async {
                blocker.armEmergencyUnlock()
            }
            return nil
        }

        if type == .keyUp && keyCode == 53 {
            DispatchQueue.main.async {
                blocker.cancelEmergencyUnlock()
            }
        } else if type == .flagsChanged
            && !(flags.contains(.maskControl) && flags.contains(.maskAlternate)) {
            DispatchQueue.main.async {
                blocker.cancelEmergencyUnlock()
            }
        }

        if FocusKeyPolicyBridge.shouldBlock(
            type: type,
            keyCode: keyCode,
            flags: flags
        ) {
            return nil
        }
        return Unmanaged.passUnretained(event)
    }
}

private enum FocusKeyPolicyBridge {
    static let emergencyHoldSeconds = FocusKeyPolicy.emergencyHoldSeconds

    static func shouldBlock(
        type: CGEventType,
        keyCode: CGKeyCode,
        flags: CGEventFlags
    ) -> Bool {
        FocusKeyPolicy.shouldBlock(
            type: type,
            keyCode: keyCode,
            flags: flags
        )
    }

    static func isEmergencyChord(
        type: CGEventType,
        keyCode: CGKeyCode,
        flags: CGEventFlags
    ) -> Bool {
        FocusKeyPolicy.isEmergencyChord(
            type: type,
            keyCode: keyCode,
            flags: flags
        )
    }
}
