import Foundation

enum AIServiceResponseParser {
    static func message(from data: Data) -> String {
        if let errorMessage = errorMessageIfPresent(from: data) {
            return errorMessage
        }
        return compactText(from: data)
    }

    static func message(from text: String) -> String {
        if let data = text.data(using: .utf8),
           let errorMessage = errorMessageIfPresent(from: data) {
            return errorMessage
        }
        return compactText(from: text)
    }

    static func errorMessageIfPresent(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        return errorMessageIfPresent(in: object)
    }

    private static func errorMessageIfPresent(in object: Any) -> String? {
        if let dictionary = object as? [String: Any] {
            return errorMessageIfPresent(in: dictionary)
        }
        if let array = object as? [Any] {
            let messages = array.compactMap { errorMessageIfPresent(in: $0) }
            return joined(messages)
        }
        return nil
    }

    private static func errorMessageIfPresent(in dictionary: [String: Any]) -> String? {
        let hasExplicitError = dictionary["error"] != nil || dictionary["errors"] != nil
        let hasOpenAIChoices = dictionary["choices"] != nil
        let hasMessageOnlyError = !hasOpenAIChoices && messageOnlyErrorKeys.contains { dictionary[$0] != nil }
        guard hasExplicitError || hasMessageOnlyError else {
            return nil
        }

        var parts: [String] = []
        if let error = dictionary["error"] {
            parts.append(contentsOf: messageParts(from: error))
        }
        if let errors = dictionary["errors"] {
            parts.append(contentsOf: messageParts(from: errors))
        }
        parts.append(contentsOf: preferredMessageKeys.compactMap { key in
            guard key != "error", key != "errors", let value = dictionary[key] else { return nil }
            return textValue(value).map { label(key, value: $0) }
        })

        let message = joined(parts)
        if let message {
            return message
        }
        return compactJSONObject(dictionary)
    }

    private static func messageParts(from value: Any) -> [String] {
        if let dictionary = value as? [String: Any] {
            var parts = preferredMessageKeys.compactMap { key in
                dictionary[key].flatMap { textValue($0).map { label(key, value: $0) } }
            }
            if parts.isEmpty {
                parts = dictionary
                    .sorted { $0.key < $1.key }
                    .prefix(8)
                    .compactMap { key, value in textValue(value).map { label(key, value: $0) } }
            }
            return parts
        }
        if let array = value as? [Any] {
            return Array(array.prefix(6)).flatMap { messageParts(from: $0) }
        }
        return textValue(value).map { [$0] } ?? []
    }

    private static func textValue(_ value: Any) -> String? {
        if let string = value as? String {
            return string.nilIfBlank
        }
        if let number = value as? NSNumber {
            return "\(number)"
        }
        if let dictionary = value as? [String: Any] {
            if let message = errorMessageIfPresent(in: dictionary) {
                return message
            }
            return compactJSONObject(dictionary)
        }
        if let array = value as? [Any] {
            return joined(Array(array.prefix(6)).compactMap { textValue($0) })
        }
        return nil
    }

    private static func label(_ key: String, value: String) -> String {
        switch key {
        case "request_id", "requestId", "id":
            return "\(key): \(value)"
        case "code", "type", "status", "param":
            return "\(key): \(value)"
        default:
            return value
        }
    }

    private static func joined(_ values: [String]) -> String? {
        var seen = Set<String>()
        let unique = values.compactMap { value -> String? in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { return nil }
            seen.insert(trimmed)
            return trimmed
        }
        guard !unique.isEmpty else { return nil }
        return unique.joined(separator: "；")
    }

    private static func compactJSONObject(_ object: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return compactText(from: text)
    }

    private static func compactText(from data: Data) -> String {
        compactText(from: String(data: data, encoding: .utf8) ?? "无法读取响应内容")
    }

    private static func compactText(from text: String) -> String {
        let trimmed = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "响应为空。" }
        return trimmed.count > 700 ? String(trimmed.prefix(700)) + "..." : trimmed
    }

    private static let preferredMessageKeys = [
        "code",
        "status",
        "type",
        "message",
        "msg",
        "detail",
        "error_message",
        "errorMessage",
        "param",
        "request_id",
        "requestId",
        "id"
    ]

    private static let messageOnlyErrorKeys = [
        "message",
        "msg",
        "detail",
        "error_message",
        "errorMessage"
    ]
}
