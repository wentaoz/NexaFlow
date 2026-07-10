import Foundation

struct RegressionTestFailure: Error, CustomStringConvertible {
    var message: String
    var file: StaticString
    var line: UInt

    var description: String {
        "\(file):\(line): \(message)"
    }
}
