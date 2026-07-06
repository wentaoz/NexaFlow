import Foundation

class XCTestCase {}

enum TestFailureRecorder {
    static var failures: [RegressionTestFailure] = []
}

struct RegressionTestFailure: Error, CustomStringConvertible {
    var message: String
    var file: StaticString
    var line: UInt

    var description: String {
        "\(file):\(line): \(message)"
    }
}

func XCTAssert(
    _ expression: @autoclosure () -> Bool,
    _ message: String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard expression() else {
        let detail = message.isEmpty ? "Assertion failed" : message
        TestFailureRecorder.failures.append(
            RegressionTestFailure(message: detail, file: file, line: line)
        )
        return
    }
}

func XCTUnwrap<T>(
    _ expression: @autoclosure () -> T?,
    _ message: String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> T {
    guard let value = expression() else {
        let detail = message.isEmpty ? "Expected non-nil value" : message
        throw RegressionTestFailure(message: detail, file: file, line: line)
    }
    return value
}
