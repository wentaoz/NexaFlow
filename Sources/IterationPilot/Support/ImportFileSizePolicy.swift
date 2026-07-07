import Foundation

enum ImportFileSizePolicy {
    static let maxSingleFileBytes: Int64 = 80 * 1_024 * 1_024
    static let maxTotalBytes: Int64 = 250 * 1_024 * 1_024

    static func validateSingleFile(_ url: URL) throws {
        guard let size = fileSize(url), size > maxSingleFileBytes else { return }
        throw ImportError.fileTooLarge(url.lastPathComponent, maxMegabytes: 80)
    }

    static func fileSize(_ url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values?.isRegularFile != false else { return nil }
        if let size = values?.fileSize {
            return Int64(size)
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value
    }
}
