import Foundation

public enum DefaultFilenameTemplate {
    public static let defaultTemplate = "focus-{date}.md"

    public static func makeFilename(
        template: String,
        date: Date,
        timeZone: TimeZone = .current
    ) -> String? {
        let trimmedTemplate = template.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmedTemplate.isEmpty else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let dateComponents = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        guard
            let year = dateComponents.year,
            let month = dateComponents.month,
            let day = dateComponents.day,
            let hour = dateComponents.hour,
            let minute = dateComponents.minute,
            let second = dateComponents.second
        else {
            return nil
        }

        let yearText = String(format: "%04d", year)
        let monthText = String(format: "%02d", month)
        let dayText = String(format: "%02d", day)
        let hourText = String(format: "%02d", hour)
        let minuteText = String(format: "%02d", minute)
        let secondText = String(format: "%02d", second)
        var expandedTemplate = trimmedTemplate
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
        for (token, replacement) in replacements {
            expandedTemplate = expandedTemplate.replacingOccurrences(
                of: token,
                with: replacement
            )
        }

        return MarkdownFilename.normalizedFilename(
            expandedTemplate,
            fallback: defaultTemplate
        )
    }
}
