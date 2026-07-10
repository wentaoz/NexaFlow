import Foundation

enum SecurityScopedResource {
    struct Resolution {
        let url: URL
        let refreshedBookmarkData: Data?
    }

    static func bookmarkData(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    static func resolve(bookmarkData: Data?, fallbackURL: URL) -> Resolution {
        guard let bookmarkData else {
            return Resolution(url: fallbackURL, refreshedBookmarkData: nil)
        }

        var isStale = false
        guard let resolvedURL = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return Resolution(url: fallbackURL, refreshedBookmarkData: nil)
        }
        let refreshedData = isStale ? try? self.bookmarkData(for: resolvedURL) : nil
        return Resolution(url: resolvedURL, refreshedBookmarkData: refreshedData)
    }

    static func access<T>(_ url: URL, _ body: () throws -> T) rethrows -> T {
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try body()
    }
}
