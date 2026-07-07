import Foundation

enum SecurityScopedResource {
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
