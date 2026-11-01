import CoreGraphics
import XCTest
@testable import FocusWriterCore

final class FocusCoreTests: XCTestCase {
    func testDurationFormats() {
        XCTAssertEqual(FocusDuration(input: "25")?.seconds, 1_500)
        XCTAssertEqual(FocusDuration(input: "45m")?.seconds, 2_700)
        XCTAssertEqual(FocusDuration(input: "1h")?.seconds, 3_600)
        XCTAssertEqual(FocusDuration(input: "1:30")?.seconds, 5_400)
        XCTAssertEqual(FocusDuration.label(minutes: 5), "5min")
        XCTAssertEqual(FocusDuration.label(minutes: 60), "1hour")
        XCTAssertEqual(FocusDuration.label(minutes: 65), "1hour 5min")
        XCTAssertEqual(FocusDuration.label(minutes: 125), "2hours 5min")
    }

    func testDurationMenuIntervals() {
        XCTAssertTrue(FocusDuration.minuteOptions.contains(60))
        XCTAssertFalse(FocusDuration.minuteOptions.contains(65))
        XCTAssertTrue(FocusDuration.minuteOptions.contains(70))
        XCTAssertTrue(FocusDuration.minuteOptions.contains(110))
        XCTAssertTrue(FocusDuration.minuteOptions.contains(120))
        XCTAssertFalse(FocusDuration.minuteOptions.contains(130))
        XCTAssertTrue(FocusDuration.minuteOptions.contains(180))
        XCTAssertTrue(FocusDuration.minuteOptions.contains(1_440))
    }

    func testInvalidDurations() {
        XCTAssertNil(FocusDuration(input: ""))
        XCTAssertNil(FocusDuration(input: "0"))
        XCTAssertNil(FocusDuration(input: "1:60"))
        XCTAssertNil(FocusDuration(input: "25h"))
        XCTAssertNil(FocusDuration(input: "abc"))
    }

    func testEditingShortcutsAreAllowed() {
        let command = CGEventFlags.maskCommand
        for key in [0, 6, 7, 8, 9, 24, 27, 69, 78] as [CGKeyCode] {
            XCTAssertFalse(
                FocusKeyPolicy.shouldBlock(type: .keyDown, keyCode: key, flags: command)
            )
        }
    }

    func testAppSwitchingShortcutsAreBlocked() {
        let command = CGEventFlags.maskCommand
        XCTAssertTrue(
            FocusKeyPolicy.shouldBlock(type: .keyDown, keyCode: 48, flags: command)
        )
        XCTAssertTrue(
            FocusKeyPolicy.shouldBlock(type: .keyDown, keyCode: 49, flags: command)
        )
        XCTAssertTrue(
            FocusKeyPolicy.shouldBlock(
                type: .keyDown,
                keyCode: 126,
                flags: .maskControl
            )
        )
        XCTAssertTrue(
            FocusKeyPolicy.shouldBlock(type: .keyDown, keyCode: 99, flags: [])
        )
    }

    func testMarkdownFileNames() {
        XCTAssertEqual(
            MarkdownFileName.normalized("notes", fallback: "fallback.md"),
            "notes.md"
        )
        XCTAssertEqual(
            MarkdownFileName.normalized("notes.txt", fallback: "fallback.md"),
            "notes.md"
        )
        XCTAssertEqual(
            MarkdownFileName.normalized("", fallback: "fallback.md"),
            "fallback.md"
        )
        XCTAssertNil(
            MarkdownFileName.normalized("../notes", fallback: "fallback.md")
        )
    }

    func testEmergencyExitChord() {
        let chord = CGEventFlags([.maskControl, .maskAlternate])
        XCTAssertTrue(
            FocusKeyPolicy.isEmergencyChord(
                type: .keyDown,
                keyCode: 53,
                flags: chord
            )
        )
        XCTAssertFalse(
            FocusKeyPolicy.isEmergencyChord(
                type: .keyDown,
                keyCode: 53,
                flags: .maskAlternate
            )
        )
    }
}
