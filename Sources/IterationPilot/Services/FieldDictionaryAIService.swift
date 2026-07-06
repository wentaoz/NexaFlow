import Foundation

struct FieldDictionaryInterpretation {
    var meaning: String
    var dataType: String
    var notes: String
    var assistantReply: String
}

enum FieldDictionaryAIService {
    static func fallbackQuestion(for definition: ReportFieldDefinition) -> String {
        let sample = definition.exampleValue.isEmpty ? "暂无样例值" : "样例值：\(definition.exampleValue)"
        let currentMeaning = definition.meaning.isEmpty ? "当前还没有含义说明" : "当前推测：\(definition.meaning)"
        return "我正在定义「\(definition.reportName)」\(definition.reportShape.label)里的字段标签「\(definition.fieldName)」。\(sample)。\(currentMeaning)。请告诉我它在业务上是什么意思、统计口径是什么，以及如果它是埋点字段，触发时机是什么。"
    }

    static func questionPrompt(for definition: ReportFieldDefinition) -> String {
        """
        你是产品数据字典助手。请针对 CSV 第一行或第一列里的一个字段标签向产品负责人提出一个清晰、具体、单轮可回答的问题，用来确认字段含义。

        要求：
        - 只输出问题本身，不要输出解释、标题或列表。
        - 问题要包含报表名、字段名、样例值。
        - 如果是埋点数据，重点询问触发时机、事件属性、统计口径。
        - 如果已有推测含义，要请求用户确认或修正。

        报表：\(definition.reportName)
        报表类型：\(definition.reportKind.label)
        表格结构：\(definition.reportShape.label)
        字段：\(definition.fieldName)
        样例值：\(definition.exampleValue.isEmpty ? "无" : definition.exampleValue)
        当前类型推断：\(definition.dataType)
        当前含义推测：\(definition.meaning.isEmpty ? "无" : definition.meaning)
        当前备注：\(definition.notes.isEmpty ? "无" : definition.notes)
        """
    }

    static func interpretationPrompt(for definition: ReportFieldDefinition, userAnswer: String) -> String {
        """
        你是产品数据字典助手。请根据用户对字段含义的回答，生成结构化字段字典。

        只输出 JSON，不要 Markdown，不要代码块。JSON schema:
        {
          "meaning": "字段业务含义，简洁但完整",
          "data_type": "string|number|date|datetime|boolean|enum|json|id",
          "notes": "统计口径、触发时机、枚举值、清洗规则或注意事项；没有就为空字符串",
          "assistant_reply": "一句话告诉用户已保存了什么"
        }

        报表：\(definition.reportName)
        报表类型：\(definition.reportKind.label)
        表格结构：\(definition.reportShape.label)
        字段：\(definition.fieldName)
        样例值：\(definition.exampleValue.isEmpty ? "无" : definition.exampleValue)
        当前类型推断：\(definition.dataType)
        当前含义推测：\(definition.meaning.isEmpty ? "无" : definition.meaning)
        当前备注：\(definition.notes.isEmpty ? "无" : definition.notes)

        用户回答：
        \(userAnswer)
        """
    }

    static func fallbackInterpretation(for definition: ReportFieldDefinition, userAnswer: String) -> FieldDictionaryInterpretation {
        let trimmed = userAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        let meaning = trimmed.isEmpty ? definition.meaning : trimmed
        let notes = definition.notes.isEmpty ? "通过字段定义问答确认。" : "\(definition.notes)\n通过字段定义问答确认。"
        return FieldDictionaryInterpretation(
            meaning: meaning,
            dataType: definition.dataType.isEmpty ? "string" : definition.dataType,
            notes: notes,
            assistantReply: "已保存「\(definition.fieldName)」的字段含义。"
        )
    }

    static func parseInterpretation(_ output: String, fallback: FieldDictionaryInterpretation) -> FieldDictionaryInterpretation {
        guard let json = jsonObjectString(from: output),
              let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            var copy = fallback
            if !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                copy.assistantReply = output.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return copy
        }

        return FieldDictionaryInterpretation(
            meaning: decoded.meaning?.nilIfBlank ?? fallback.meaning,
            dataType: decoded.dataType?.nilIfBlank ?? fallback.dataType,
            notes: decoded.notes ?? fallback.notes,
            assistantReply: decoded.assistantReply?.nilIfBlank ?? fallback.assistantReply
        )
    }

    private static func jsonObjectString(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start <= end else {
            return nil
        }
        return String(text[start...end])
    }

    private struct Response: Decodable {
        var meaning: String?
        var dataType: String?
        var notes: String?
        var assistantReply: String?

        enum CodingKeys: String, CodingKey {
            case meaning
            case dataType = "data_type"
            case dataTypeCamel = "dataType"
            case notes
            case assistantReply = "assistant_reply"
            case assistantReplyCamel = "assistantReply"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            meaning = try container.decodeIfPresent(String.self, forKey: .meaning)
            dataType = try container.decodeIfPresent(String.self, forKey: .dataType)
                ?? container.decodeIfPresent(String.self, forKey: .dataTypeCamel)
            notes = try container.decodeIfPresent(String.self, forKey: .notes)
            assistantReply = try container.decodeIfPresent(String.self, forKey: .assistantReply)
                ?? container.decodeIfPresent(String.self, forKey: .assistantReplyCamel)
        }
    }
}
