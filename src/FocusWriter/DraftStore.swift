import Foundation

final class DraftStore {
    private let fileURL: URL

    init() {
        let fileManager = FileManager.default
        let baseURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let appFolder = baseURL
            .appendingPathComponent("WritingJail", isDirectory: true)
        fileURL = appFolder
            .appendingPathComponent("draft.txt", isDirectory: false)

        let legacyDraftURL = baseURL
            .appendingPathComponent("FocusWriter", isDirectory: true)
            .appendingPathComponent("draft.txt", isDirectory: false)
        if !fileManager.fileExists(atPath: fileURL.path),
            fileManager.fileExists(atPath: legacyDraftURL.path) {
            try? fileManager.createDirectory(
                at: appFolder,
                withIntermediateDirectories: true
            )
            try? fileManager.copyItem(at: legacyDraftURL, to: fileURL)
        }
    }

    func load() -> String {
        (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    }

    func save(_ text: String) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            NSLog("WritingJail could not save the draft: %@", error.localizedDescription)
        }
    }
}
