import Foundation

public enum MarkdownFilename {
    public static func normalizedFilename(
        _ input: String,
        fallback: String
    ) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let filenameCandidate = trimmed.isEmpty ? fallback : trimmed
        guard
            !filenameCandidate.contains("/"),
            filenameCandidate != ".",
            filenameCandidate != ".."
        else {
            return nil
        }

        let filenameObject = filenameCandidate as NSString
        let baseFilename = filenameObject.deletingPathExtension
        guard !baseFilename.isEmpty else {
            return nil
        }
        return "\(baseFilename).md"
    }
}
