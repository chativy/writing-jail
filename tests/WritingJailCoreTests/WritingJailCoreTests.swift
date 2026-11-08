import CoreGraphics
import XCTest
@testable import WritingJailCore

final class WritingJailCoreTests: XCTestCase {
    func testDurationFormats() {
        XCTAssertEqual(FocusSessionDuration(input: "25")?.totalSeconds, 1_500)
        XCTAssertEqual(FocusSessionDuration(input: "45m")?.totalSeconds, 2_700)
        XCTAssertEqual(FocusSessionDuration(input: "1h")?.totalSeconds, 3_600)
        XCTAssertEqual(FocusSessionDuration(input: "1:30")?.totalSeconds, 5_400)
        XCTAssertEqual(FocusSessionDuration.displayLabel(forMinutes: 5), "5min")
        XCTAssertEqual(FocusSessionDuration.displayLabel(forMinutes: 60), "1hour")
        XCTAssertEqual(FocusSessionDuration.displayLabel(forMinutes: 65), "1hour 5min")
        XCTAssertEqual(FocusSessionDuration.displayLabel(forMinutes: 125), "2hours 5min")
    }

    func testDurationMenuIntervals() {
        XCTAssertTrue(FocusSessionDuration.availableMinuteOptions.contains(60))
        XCTAssertFalse(FocusSessionDuration.availableMinuteOptions.contains(65))
        XCTAssertTrue(FocusSessionDuration.availableMinuteOptions.contains(70))
        XCTAssertTrue(FocusSessionDuration.availableMinuteOptions.contains(110))
        XCTAssertTrue(FocusSessionDuration.availableMinuteOptions.contains(120))
        XCTAssertFalse(FocusSessionDuration.availableMinuteOptions.contains(130))
        XCTAssertTrue(FocusSessionDuration.availableMinuteOptions.contains(180))
        XCTAssertTrue(FocusSessionDuration.availableMinuteOptions.contains(1_440))
    }

    func testInvalidDurations() {
        XCTAssertNil(FocusSessionDuration(input: ""))
        XCTAssertNil(FocusSessionDuration(input: "0"))
        XCTAssertNil(FocusSessionDuration(input: "1:60"))
        XCTAssertNil(FocusSessionDuration(input: "25h"))
        XCTAssertNil(FocusSessionDuration(input: "abc"))
    }

    func testEditingShortcutsAreAllowed() {
        let command = CGEventFlags.maskCommand
        for key in [0, 6, 7, 8, 9, 24, 27, 69, 78] as [CGKeyCode] {
            XCTAssertFalse(
                FocusKeyboardPolicy.shouldBlockKeyboardEvent(type: .keyDown, keyCode: key, flags: command)
            )
        }
    }

    func testAppSwitchingShortcutsAreBlocked() {
        let command = CGEventFlags.maskCommand
        XCTAssertTrue(
            FocusKeyboardPolicy.shouldBlockKeyboardEvent(type: .keyDown, keyCode: 48, flags: command)
        )
        XCTAssertTrue(
            FocusKeyboardPolicy.shouldBlockKeyboardEvent(type: .keyDown, keyCode: 49, flags: command)
        )
        XCTAssertTrue(
            FocusKeyboardPolicy.shouldBlockKeyboardEvent(
                type: .keyDown,
                keyCode: 126,
                flags: .maskControl
            )
        )
        XCTAssertTrue(
            FocusKeyboardPolicy.shouldBlockKeyboardEvent(type: .keyDown, keyCode: 99, flags: [])
        )
    }

    func testMarkdownFilenames() {
        XCTAssertEqual(
            MarkdownFilename.normalizedFilename("notes", fallback: "fallback.md"),
            "notes.md"
        )
        XCTAssertEqual(
            MarkdownFilename.normalizedFilename("notes.txt", fallback: "fallback.md"),
            "notes.md"
        )
        XCTAssertEqual(
            MarkdownFilename.normalizedFilename("", fallback: "fallback.md"),
            "fallback.md"
        )
        XCTAssertNil(
            MarkdownFilename.normalizedFilename("../notes", fallback: "fallback.md")
        )
    }

    func testDefaultFilenameTemplates() {
        let date = DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(secondsFromGMT: 0),
            year: 2026,
            month: 11,
            day: 8,
            hour: 9,
            minute: 7,
            second: 5
        ).date!
        let timeZone = TimeZone(secondsFromGMT: 0)!

        XCTAssertEqual(
            DefaultFilenameTemplate.makeFilename(
                template: "focus-{date}",
                date: date,
                timeZone: timeZone
            ),
            "focus-2026-11-08.md"
        )
        XCTAssertEqual(
            DefaultFilenameTemplate.makeFilename(
                template: "{yyyy}-{MM}-{dd}_{HH}-{mm}-{ss}",
                date: date,
                timeZone: timeZone
            ),
            "2026-11-08_09-07-05.md"
        )
        XCTAssertEqual(
            DefaultFilenameTemplate.makeFilename(
                template: "entry-{datetime}.txt",
                date: date,
                timeZone: timeZone
            ),
            "entry-2026-11-08-09-07-05.md"
        )
        XCTAssertNil(
            DefaultFilenameTemplate.makeFilename(
                template: "   ",
                date: date
            )
        )
        XCTAssertNil(
            DefaultFilenameTemplate.makeFilename(
                template: "../{date}",
                date: date
            )
        )
    }

    func testEmergencyExitChord() {
        let chord = CGEventFlags([.maskControl, .maskAlternate])
        XCTAssertTrue(
            FocusKeyboardPolicy.isEmergencyExitChord(
                type: .keyDown,
                keyCode: 53,
                flags: chord
            )
        )
        XCTAssertFalse(
            FocusKeyboardPolicy.isEmergencyExitChord(
                type: .keyDown,
                keyCode: 53,
                flags: .maskAlternate
            )
        )
    }
}
