import Foundation

public enum MarkdownFileName {
    public static func normalizedFilename(
        _ input: String,
        fallback: String
    ) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmed.isEmpty ? fallback : trimmed
        guard
            !candidate.contains("/"),
            candidate != ".",
            candidate != ".."
        else {
            return nil
        }

        let path = candidate as NSString
        let baseName = path.deletingPathExtension
        guard !baseName.isEmpty else {
            return nil
        }
        return "\(baseName).md"
    }
}
