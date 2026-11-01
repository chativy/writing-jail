import Foundation

final class ScopedResourceAccess {
    private var activeURL: URL?
    private var isAccessing = false

    var url: URL? {
        activeURL
    }

    func retain(_ url: URL, bookmarkKey: String? = nil) {
        release()
        activeURL = url
        isAccessing = url.startAccessingSecurityScopedResource()

        guard let bookmarkKey,
            let bookmarkData = try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        else {
            return
        }
        UserDefaults.standard.set(bookmarkData, forKey: bookmarkKey)
    }

    func restore(bookmarkKey: String, fallbackPathKey: String) -> URL? {
        release()

        if let bookmarkData = UserDefaults.standard.data(forKey: bookmarkKey) {
            var isStale = false
            if let resolvedURL = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                activeURL = resolvedURL
                isAccessing = resolvedURL.startAccessingSecurityScopedResource()
                return resolvedURL
            }
        }

        guard let savedPath = UserDefaults.standard.string(
            forKey: fallbackPathKey
        ) else {
            return nil
        }
        let fallbackURL = URL(fileURLWithPath: savedPath)
        activeURL = fallbackURL
        isAccessing = fallbackURL.startAccessingSecurityScopedResource()
        return fallbackURL
    }

    func release() {
        if isAccessing {
            activeURL?.stopAccessingSecurityScopedResource()
        }
        activeURL = nil
        isAccessing = false
    }
}
