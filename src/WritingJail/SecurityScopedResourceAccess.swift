import Foundation

final class SecurityScopedResourceAccess {
    private var retainedURL: URL?
    private var hasSecurityScope = false

    var activeResourceURL: URL? {
        retainedURL
    }

    func retainAccess(to url: URL, bookmarkKey: String? = nil) {
        releaseAccess()
        retainedURL = url
        hasSecurityScope = url.startAccessingSecurityScopedResource()

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

    func restoreAccess(bookmarkKey: String, fallbackPathKey: String) -> URL? {
        releaseAccess()

        if let bookmarkData = UserDefaults.standard.data(forKey: bookmarkKey) {
            var isStale = false
            if let resolvedURL = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                retainedURL = resolvedURL
                hasSecurityScope = resolvedURL.startAccessingSecurityScopedResource()
                return resolvedURL
            }
        }

        guard let savedPath = UserDefaults.standard.string(
            forKey: fallbackPathKey
        ) else {
            return nil
        }
        let fallbackURL = URL(fileURLWithPath: savedPath)
        retainedURL = fallbackURL
        hasSecurityScope = fallbackURL.startAccessingSecurityScopedResource()
        return fallbackURL
    }

    func releaseAccess() {
        if hasSecurityScope {
            retainedURL?.stopAccessingSecurityScopedResource()
        }
        retainedURL = nil
        hasSecurityScope = false
    }
}
