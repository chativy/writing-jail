import Foundation

public struct FocusDuration: Equatable, Sendable {
    public let seconds: TimeInterval

    public static var minuteOptions: [Int] {
        Array(stride(from: 5, through: 60, by: 5))
            + Array(stride(from: 70, through: 110, by: 10))
            + Array(stride(from: 120, through: 1_440, by: 60))
    }

    public init?(input: String) {
        let value = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !value.isEmpty else {
            return nil
        }

        let totalSeconds: Int

        if value.contains(":") {
            let parts = value.split(separator: ":", omittingEmptySubsequences: false)
            guard
                parts.count == 2,
                let hours = Int(parts[0]),
                let minutes = Int(parts[1]),
                (0...59).contains(minutes)
            else {
                return nil
            }
            totalSeconds = (hours * 60 + minutes) * 60
        } else {
            let hasHourSuffix = value.hasSuffix("h")
            let hasMinuteSuffix = value.hasSuffix("m")
            let numberPart = (hasHourSuffix || hasMinuteSuffix)
                ? String(value.dropLast())
                : value

            guard let number = Int(numberPart) else {
                return nil
            }
            totalSeconds = number * (hasHourSuffix ? 3600 : 60)
        }

        guard totalSeconds > 0, totalSeconds <= 24 * 60 * 60 else {
            return nil
        }
        seconds = TimeInterval(totalSeconds)
    }

    public var displayMinutes: Int {
        max(1, Int(seconds / 60))
    }

    public static func label(minutes: Int) -> String {
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours == 0 {
            return "\(minutes)min"
        }
        let hourUnit = hours == 1 ? "hour" : "hours"
        if remainingMinutes == 0 {
            return "\(hours)\(hourUnit)"
        }
        return "\(hours)\(hourUnit) \(remainingMinutes)min"
    }
}
