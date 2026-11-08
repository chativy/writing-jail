import Foundation

public enum DefaultFileNameFormat {
    public static let defaultFormat = "focus-{date}.md"

    public static func fileName(
        format: String,
        date: Date,
        timeZone: TimeZone = .current
    ) -> String? {
        let trimmed = format.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        guard
            let year = components.year,
            let month = components.month,
            let day = components.day,
            let hour = components.hour,
            let minute = components.minute,
            let second = components.second
        else {
            return nil
        }

        let yearText = String(format: "%04d", year)
        let monthText = String(format: "%02d", month)
        let dayText = String(format: "%02d", day)
        let hourText = String(format: "%02d", hour)
        let minuteText = String(format: "%02d", minute)
        let secondText = String(format: "%02d", second)
        var result = trimmed
        let replacements = [
            ("{datetime}", "\(yearText)-\(monthText)-\(dayText)-\(hourText)-\(minuteText)-\(secondText)"),
            ("{date}", "\(yearText)-\(monthText)-\(dayText)"),
            ("{time}", "\(hourText)-\(minuteText)-\(secondText)"),
            ("{yyyy}", yearText),
            ("{MM}", monthText),
            ("{dd}", dayText),
            ("{HH}", hourText),
            ("{mm}", minuteText),
            ("{ss}", secondText)
        ]
        for (token, value) in replacements {
            result = result.replacingOccurrences(of: token, with: value)
        }

        return MarkdownFileName.normalized(
            result,
            fallback: defaultFormat
        )
    }
}
