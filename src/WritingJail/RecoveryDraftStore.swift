import Foundation

final class RecoveryDraftStore {
    private let draftFileURL: URL

    init() {
        let fileManager = FileManager.default
        let baseURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let writingJailFolder = baseURL
            .appendingPathComponent("WritingJail", isDirectory: true)
        draftFileURL = writingJailFolder
            .appendingPathComponent("draft.txt", isDirectory: false)

        let legacyDraftURL = baseURL
            .appendingPathComponent("FocusWriter", isDirectory: true)
            .appendingPathComponent("draft.txt", isDirectory: false)
        if !fileManager.fileExists(atPath: draftFileURL.path),
            fileManager.fileExists(atPath: legacyDraftURL.path) {
            try? fileManager.createDirectory(
                at: writingJailFolder,
                withIntermediateDirectories: true
            )
            try? fileManager.copyItem(at: legacyDraftURL, to: draftFileURL)
        }
    }

    func loadText() -> String {
        (try? String(contentsOf: draftFileURL, encoding: .utf8)) ?? ""
    }

    func saveText(_ text: String) {
        do {
            try FileManager.default.createDirectory(
                at: draftFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try text.write(to: draftFileURL, atomically: true, encoding: .utf8)
        } catch {
            NSLog("WritingJail could not save the draft: %@", error.localizedDescription)
        }
    }
}
