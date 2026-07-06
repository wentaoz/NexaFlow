import Foundation

enum AnalysisHarnessTrustTuning {
    static let ambiguousScoreGapThreshold = 0.15
    static let contractConfirmationThreshold = 0.55
    static let contractPassThreshold = 0.75
    static let contributionShareThreshold = 0.03
}

enum MetricUnitNormalizer {
    enum CanonicalUnit: String, Hashable {
        case mxn
        case person
        case transaction
        case percent
        case percentagePoint
        case mxnPerPerson
        case mxnPerTransaction
        case transactionPerPerson
        case amount
        case unknown
    }

    static func normalize(unit: String, label: String = "", context: String = "") -> CanonicalUnit {
        let combined = "\(unit) \(label) \(context)".normalizedKey
        if combined.contains("百分点") { return .percentagePoint }
        if combined.contains("人均交易金额") || combined.contains("客单价") {
            return .mxnPerPerson
        }
        if combined.contains("笔均交易金额") {
            return .mxnPerTransaction
        }
        if combined.contains("人均交易笔数") {
            return .transactionPerPerson
        }
        if combined.contains("mxn/人") || combined.contains("比索/用户") || combined.contains("比索/人") || combined.contains("金额/人") {
            return .mxnPerPerson
        }
        if combined.contains("mxn/笔") || combined.contains("mxn/订单") || combined.contains("比索/订单") || combined.contains("比索/笔") || combined.contains("金额/笔") {
            return .mxnPerTransaction
        }
        if combined.contains("笔/人") || combined.contains("次/用户") || combined.contains("订单/用户") || combined.contains("交易/用户") {
            return .transactionPerPerson
        }
        if combined.contains("%") || combined.contains("百分比") || combined.contains("增长率") || combined.contains("占比") || combined.contains("率") {
            return .percent
        }
        if combined.contains("mxn") || combined.contains("墨西哥比索") || combined.contains("比索") || combined.contains("金额") || combined.contains("客单") {
            return .mxn
        }
        if combined.contains("人数") || combined.contains("用户") || combined.contains("人") {
            return .person
        }
        if combined.contains("笔数") || combined.contains("订单") || combined.contains("笔") || combined.contains("次数") {
            return .transaction
        }
        return .unknown
    }

    static func compatible(resultUnit: CanonicalUnit, occurrenceUnit: CanonicalUnit) -> Bool {
        if occurrenceUnit == .unknown || resultUnit == .unknown { return true }
        if resultUnit == occurrenceUnit { return true }
        if resultUnit == .amount, occurrenceUnit == .mxn { return true }
        if resultUnit == .mxn, occurrenceUnit == .amount { return true }
        return false
    }
}

enum MetricValueNormalizer {
    static func number(from raw: String) -> Double? {
        var multiplier = 1.0
        let scaleProbe = raw
            .replacingOccurrences(of: "MXN", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "墨西哥比索", with: "")
            .replacingOccurrences(of: "比索", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.contains("亿") {
            multiplier = 100_000_000
        } else if raw.contains("百万")
            || scaleProbe.range(of: #"[-+]?\d+(?:\.\d+)?\s*[mM]\b"#, options: .regularExpression) != nil {
            multiplier = 1_000_000
        } else if raw.contains("万") {
            multiplier = 10_000
        } else if scaleProbe.range(of: #"[-+]?\d+(?:\.\d+)?\s*[kK]\b"#, options: .regularExpression) != nil {
            multiplier = 1_000
        }
        var cleaned = raw
            .replacingOccurrences(of: "约为", with: "")
            .replacingOccurrences(of: "大约", with: "")
            .replacingOccurrences(of: "近似", with: "")
            .replacingOccurrences(of: "接近", with: "")
            .replacingOccurrences(of: "约", with: "")
            .replacingOccurrences(of: "近", with: "")
            .replacingOccurrences(of: "≈", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "MXN", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "墨西哥比索", with: "")
            .replacingOccurrences(of: "比索", with: "")
            .replacingOccurrences(of: "人民币", with: "")
            .replacingOccurrences(of: "美元", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "¥", with: "")
            .replacingOccurrences(of: "百万", with: "")
            .replacingOccurrences(of: "万", with: "")
            .replacingOccurrences(of: "亿", with: "")
            .replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.replacingOccurrences(of: #"[kKmM]\b"#, with: "", options: .regularExpression)
        return Double(cleaned).map { $0 * multiplier }
    }
}

struct AnswerNumberTraceReport: Hashable {
    var traces: [AnswerNumberTrace]

    var blockingTraces: [AnswerNumberTrace] {
        traces.filter { $0.status == .unmatched || $0.status == .ambiguous }
    }

    var hasBlockingTrace: Bool { !blockingTraces.isEmpty }
}

enum AnswerNumberTracer {
    private struct Occurrence {
        var rawText: String
        var value: Double?
        var isPercent: Bool
        var isApproximate: Bool
        var unitHint: String
        var canonicalUnit: MetricUnitNormalizer.CanonicalUnit
        var context: String
    }

    private struct Candidate {
        var result: MetricResult
        var score: Double
        var tolerance: Double
        var delta: Double
    }

    static func trace(report: String, verifiedResults: [MetricResult]) -> AnswerNumberTraceReport {
        guard !verifiedResults.isEmpty else {
            return AnswerNumberTraceReport(traces: [])
        }
        let answerText = directAnswerSection(in: report)
        let occurrences = extractOccurrences(from: answerText)
        let traces = occurrences.map { occurrence in
            trace(occurrence: occurrence, verifiedResults: verifiedResults)
        }
        return AnswerNumberTraceReport(traces: traces)
    }

    private static func trace(occurrence: Occurrence, verifiedResults: [MetricResult]) -> AnswerNumberTrace {
        guard let value = occurrence.value else {
            return AnswerNumberTrace(
                rawText: occurrence.rawText,
                normalizedValue: nil,
                unitHint: occurrence.unitHint,
                contextSnippet: occurrence.context,
                status: .ignored,
                reason: "不是可比较数字。"
            )
        }

        let candidates = verifiedResults.compactMap { result -> Candidate? in
            guard let rawValue = result.rawValue else { return nil }
            let resultUnit = MetricUnitNormalizer.normalize(unit: result.unit, label: result.label)
            guard MetricUnitNormalizer.compatible(resultUnit: resultUnit, occurrenceUnit: occurrence.canonicalUnit) else {
                return nil
            }
            let candidateValue = comparableValue(rawValue, result: result, occurrence: occurrence)
            let tolerance = tolerance(for: result, occurrence: occurrence, candidateValue: candidateValue)
            let delta = abs(candidateValue - value)
            guard delta <= tolerance else { return nil }
            return Candidate(
                result: result,
                score: score(result: result, occurrence: occurrence, delta: delta, tolerance: tolerance),
                tolerance: tolerance,
                delta: delta
            )
        }
        .sorted {
            if abs($0.score - $1.score) > 0.0001 { return $0.score > $1.score }
            return $0.delta < $1.delta
        }

        guard let top = candidates.first else {
            return AnswerNumberTrace(
                rawText: occurrence.rawText,
                normalizedValue: value,
                unitHint: occurrence.unitHint,
                contextSnippet: occurrence.context,
                status: .unmatched,
                toleranceDescription: toleranceDescription(for: occurrence),
                reason: "未找到落入容差区间的 verified result。"
            )
        }

        if candidates.count >= 2,
           top.score - candidates[1].score < AnalysisHarnessTrustTuning.ambiguousScoreGapThreshold {
            return AnswerNumberTrace(
                rawText: occurrence.rawText,
                normalizedValue: value,
                unitHint: occurrence.unitHint,
                contextSnippet: occurrence.context,
                status: .ambiguous,
                toleranceDescription: toleranceDescription(for: occurrence),
                candidateLabels: candidates.prefix(5).map { $0.result.label },
                candidateResultIDs: candidates.prefix(5).map { $0.result.id },
                reason: "多个 verified result 同时落入容差区间，且评分差距小于 \(AnalysisHarnessTrustTuning.ambiguousScoreGapThreshold)。"
            )
        }

        return AnswerNumberTrace(
            rawText: occurrence.rawText,
            normalizedValue: value,
            unitHint: occurrence.unitHint,
            contextSnippet: occurrence.context,
            status: occurrence.isApproximate ? .approximateMatched : .matched,
            matchedResultID: top.result.id,
            matchedResultLabel: top.result.label,
            toleranceDescription: toleranceDescription(for: top.result, occurrence: occurrence, tolerance: top.tolerance),
            candidateLabels: candidates.prefix(5).map { $0.result.label },
            candidateResultIDs: candidates.prefix(5).map { $0.result.id },
            reason: occurrence.isApproximate ? "近似表述已按放宽容差匹配。" : "数字已匹配本地 verified result。"
        )
    }

    private static func directAnswerSection(in report: String) -> String {
        let lines = report.components(separatedBy: .newlines)
        guard let start = lines.firstIndex(where: { isDirectAnswerHeading(normalizedHeading($0)) }) else {
            return report
        }
        guard start + 1 < lines.count else { return "" }
        let following = lines[(start + 1)...]
        if let endOffset = following.firstIndex(where: { line in
            line.trimmingCharacters(in: .whitespaces).hasPrefix("##")
        }) {
            return following[..<endOffset].joined(separator: "\n")
        }
        return following.joined(separator: "\n")
    }

    private static func normalizedHeading(_ line: String) -> String {
        line.replacingOccurrences(of: "#", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^\d+[\.\、]\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: " ", with: "")
    }

    private static func isDirectAnswerHeading(_ heading: String) -> Bool {
        [
            "直接回答你的问题",
            "直接回答",
            "直接结论",
            "核心结论",
            "核心判断",
            "结论",
            "回答",
            "结论摘要"
        ].contains(heading)
    }

    private static func extractOccurrences(from text: String) -> [Occurrence] {
        let pattern = #"(?:(?:约|大约|约为|近似|接近|近|≈)\s*)?(?:MXN\s*)?[-+]?\d+(?:,\d{3})*(?:\.\d+)?(?:\s*(?:百万|万|亿|[kKmM]\b))?(?:\s*%)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: nsRange).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            let raw = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            let context = lineContaining(range: range, in: text)
            let nearby = nearbySnippet(range: range, in: text)
            guard !hasAlphanumericAdjacency(range: range, in: text),
                  !shouldIgnore(rawText: raw, context: context, nearby: nearby) else { return nil }
            let unit = unitHint(rawText: raw, context: nearby)
            let canonicalUnit = MetricUnitNormalizer.normalize(unit: unit, context: unit.isEmpty ? nearby : "")
            return Occurrence(
                rawText: raw,
                value: normalizedNumber(from: raw),
                isPercent: raw.contains("%") || context.contains("百分点"),
                isApproximate: isApproximate(rawText: raw, nearby: nearby),
                unitHint: unit,
                canonicalUnit: canonicalUnit,
                context: context
            )
        }
    }

    private static func isApproximate(rawText: String, nearby: String) -> Bool {
        rawText.contains("约")
            || rawText.contains("近")
            || nearby.contains("约为")
            || nearby.contains("大约")
            || nearby.contains("近似")
            || nearby.contains("接近")
    }

    private static func shouldIgnore(rawText: String, context: String, nearby: String) -> Bool {
        let compact = rawText
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = Double(compact),
           value >= 1900, value <= 2100,
           !rawText.contains("%"),
           !rawText.contains("万"),
           !rawText.contains("亿") {
            return true
        }
        if let value = normalizedNumber(from: rawText),
           abs(value) < 100,
           !rawText.contains("%"),
           isAuditOrCoverageCount(valueText: compact, context: context, nearby: nearby) {
            return true
        }
        if let value = normalizedNumber(from: rawText),
           abs(value) < 100,
           !rawText.contains("%"),
           !context.contains("人"),
           !context.contains("笔"),
           !context.localizedCaseInsensitiveContains("MXN"),
           !context.contains("金额"),
           !context.contains("率"),
           !context.contains("占比") {
            return true
        }
        if isClearlyEvidenceCitationNumber(context: context, nearby: nearby) {
            return true
        }
        return false
    }

    private static func isClearlyEvidenceCitationNumber(context: String, nearby: String) -> Bool {
        let combined = "\(context) \(nearby)"
        let localMetricWords = ["交易人数", "交易金额", "交易笔数", "人均", "笔均", "转化率", "通过率", "注册", "授信", "还款", "逾期", "金额", "人数", "笔数"]
        let hasLocalMetricContext = localMetricWords.contains { combined.localizedCaseInsensitiveContains($0) }
        if hasLocalMetricContext {
            return false
        }
        if combined.range(of: #"\[[KCEJDT]\d+\]"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }
        let evidenceWords = ["知识库", "Confluence", "Jira", "钉钉", "外部", "政策", "竞品", "新闻", "资料", "证据", "来源", "采集"]
        return evidenceWords.contains { combined.localizedCaseInsensitiveContains($0) }
    }

    private static func hasAlphanumericAdjacency(range: Range<String.Index>, in text: String) -> Bool {
        let adjacentScalars: [UnicodeScalar] = [
            range.lowerBound > text.startIndex ? text[text.index(before: range.lowerBound)].unicodeScalars.first : nil,
            range.upperBound < text.endIndex ? text[range.upperBound].unicodeScalars.first : nil
        ].compactMap { $0 }
        return adjacentScalars.contains { scalar in
            (48...57).contains(Int(scalar.value))
                || (65...90).contains(Int(scalar.value))
                || (97...122).contains(Int(scalar.value))
        }
    }

    private static func nearbySnippet(range: Range<String.Index>, in text: String) -> String {
        let lower = text.index(range.lowerBound, offsetBy: -8, limitedBy: text.startIndex) ?? text.startIndex
        let upper = text.index(range.upperBound, offsetBy: 8, limitedBy: text.endIndex) ?? text.endIndex
        return String(text[lower..<upper])
    }

    private static func isAuditOrCoverageCount(valueText: String, context: String, nearby: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: valueText)
        let countUnitPattern = #"(?<![\d.])"# + escaped + #"\s*(个周期|张表|条|项|次|个问题)"#
        let countUnitFound = context.range(of: countUnitPattern, options: .regularExpression) != nil
            || nearby.range(of: countUnitPattern, options: .regularExpression) != nil
        guard countUnitFound else { return false }
        let auditWords = ["覆盖", "截至", "校验", "读取", "问题", "证据", "资料", "选表", "表格", "修复", "尝试", "内部", "审计"]
        return auditWords.contains { context.contains($0) }
    }

    private static func lineContaining(range: Range<String.Index>, in text: String) -> String {
        let lower = text[..<range.lowerBound].lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
        let upper = text[range.upperBound...].firstIndex(of: "\n") ?? text.endIndex
        return String(text[lower..<upper])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedNumber(from raw: String) -> Double? {
        MetricValueNormalizer.number(from: raw)
    }

    private static func unitHint(rawText: String, context: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: rawText.trimmingCharacters(in: .whitespacesAndNewlines))
        if context.range(of: escaped + #"\s*(%|百分比)"#, options: .regularExpression) != nil {
            return "%"
        }
        if context.range(of: escaped + #"\s*(MXN/人|MXN/用户|比索/人|比索/用户|金额/人)"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return "MXN/人"
        }
        if context.range(of: escaped + #"\s*(MXN/笔|MXN/订单|比索/笔|比索/订单|金额/笔)"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return "MXN/笔"
        }
        if context.range(of: escaped + #"\s*(笔/人|笔/用户|次/用户|订单/用户|交易/用户)"#, options: .regularExpression) != nil {
            return "笔/人"
        }
        if context.range(of: escaped + #"\s*(MXN|墨西哥比索|比索)"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return "金额"
        }
        if context.range(of: escaped + #"\s*(人|用户|人数)"#, options: .regularExpression) != nil {
            return "人"
        }
        if context.range(of: escaped + #"\s*(笔|次|订单)"#, options: .regularExpression) != nil {
            return "笔"
        }
        if rawText.contains("%") || context.contains("百分点") || context.contains("增长率") || context.contains("占比") || context.contains("率") {
            return "%"
        }
        if context.localizedCaseInsensitiveContains("MXN") || context.contains("金额") || context.contains("客单") || context.contains("笔均") {
            return "金额"
        }
        if context.contains("笔") || context.contains("次数") {
            return "笔"
        }
        if context.contains("人") || context.contains("用户") {
            return "人"
        }
        return ""
    }

    private static func comparableValue(_ value: Double, result: MetricResult, occurrence: Occurrence) -> Double {
        if result.format == .percent,
           !occurrence.rawText.contains("%"),
           abs(value) <= 1,
           occurrence.canonicalUnit == .percent {
            return value * 100
        }
        if occurrence.isPercent, result.format != .percent, abs(value) <= 1 {
            return value * 100
        }
        return value
    }

    private static func tolerance(for result: MetricResult, occurrence: Occurrence, candidateValue: Double) -> Double {
        let base: Double
        let resultUnit = MetricUnitNormalizer.normalize(unit: result.unit, label: result.label)
        if result.format == .percent || occurrence.isPercent || resultUnit == .percent || resultUnit == .percentagePoint {
            base = 0.01
        } else if result.format == .currency || result.unit.localizedCaseInsensitiveContains("MXN") || occurrence.unitHint == "金额" {
            base = max(0.01, min(abs(candidateValue) * 0.0001, 1))
        } else if result.format == .integer || occurrence.unitHint == "人" || occurrence.unitHint == "笔" {
            base = 1
        } else if result.unit.contains("/") {
            base = max(0.01, abs(candidateValue) * 0.001)
        } else {
            base = max(0.01, abs(candidateValue) * 0.001)
        }
        return occurrence.isApproximate ? max(base, abs(candidateValue) * 0.01) : base
    }

    private static func toleranceDescription(for occurrence: Occurrence) -> String {
        if occurrence.isApproximate { return "近似表述容差 1%" }
        if occurrence.isPercent { return "百分比容差 0.01 个百分点" }
        switch occurrence.unitHint {
        case "金额": return "金额容差 0.01%，最多 1 个显示单位"
        case "人", "笔": return "整数容差 ≤ 1"
        default: return "默认容差 0.1%"
        }
    }

    private static func toleranceDescription(for result: MetricResult, occurrence: Occurrence, tolerance: Double) -> String {
        "\(toleranceDescription(for: occurrence))；实际容差 \(String(format: "%.4f", tolerance))；结果 \(result.label)"
    }

    private static func score(result: MetricResult, occurrence: Occurrence, delta: Double, tolerance: Double) -> Double {
        let contextKey = occurrence.context.normalizedKey
        let labelKey = result.label.normalizedKey
        var score = 0.0
        if !labelKey.isEmpty, contextKey.contains(labelKey) {
            score += 0.45
        } else if semanticOverlap(result.label, occurrence.context) {
            score += 0.30
        }
        if periodMatches(label: result.label, context: occurrence.context) {
            score += 0.20
        }
        if unitMatches(result: result, occurrence: occurrence) {
            score += 0.20
        }
        score += max(0, 0.15 * (1 - min(delta / max(tolerance, 0.000001), 1)))
        return score
    }

    private static func semanticOverlap(_ label: String, _ context: String) -> Bool {
        let labelKey = label.normalizedKey
        let contextKey = context.normalizedKey
        let tokens = ["交易人数", "交易金额", "交易笔数", "人均交易金额", "人均交易笔数", "笔均交易金额", "增长率", "人数", "金额", "笔数"]
        return tokens.contains { token in
            labelKey.contains(token.normalizedKey) && contextKey.contains(token.normalizedKey)
        }
    }

    private static func periodMatches(label: String, context: String) -> Bool {
        let labelKey = label.normalizedKey
        let contextKey = context.normalizedKey
        let pairs = [
            ("2025H2", ["2025h2", "2025 h2", "2025下半年", "去年下半年"]),
            ("2026H1", ["2026h1", "2026 h1", "2026上半年", "今年上半年"]),
            ("H1", ["h1", "上半年"]),
            ("H2", ["h2", "下半年"])
        ]
        return pairs.contains { labelToken, contextTokens in
            labelKey.contains(labelToken.normalizedKey) && contextTokens.contains { contextKey.contains($0.normalizedKey) }
        }
    }

    private static func unitMatches(result: MetricResult, occurrence: Occurrence) -> Bool {
        let resultUnit = MetricUnitNormalizer.normalize(unit: result.unit, label: result.label)
        return MetricUnitNormalizer.compatible(resultUnit: resultUnit, occurrenceUnit: occurrence.canonicalUnit)
    }
}

struct DataContractValidationOutput {
    var summary: DataContractValidationSummary
    var issues: [ValidationIssue]
}

enum DataContractValidator {
    static func validate(manifests: [TableManifest]) -> DataContractValidationOutput {
        var issues: [ValidationIssue] = []
        var warnings: [String] = []
        for manifest in manifests {
            if manifest.columns.isEmpty {
                issues.append(ValidationIssue(
                    severity: .fatal,
                    code: .dataContractViolation,
                    stage: .dataContractValidation,
                    message: "\(manifest.displayName) 没有可读取字段，无法进入分析。"
                ))
                continue
            }
            if manifest.dateRanges.isEmpty {
                warnings.append("\(manifest.displayName) 未识别到明确时间范围。")
                issues.append(ValidationIssue(
                    severity: .warning,
                    code: .dataContractViolation,
                    stage: .dataContractValidation,
                    message: "\(manifest.displayName) 未识别到明确时间范围，时间对比结论需要保守。"
                ))
            }
            if let understanding = manifest.understanding {
                if understanding.confidence < AnalysisHarnessTrustTuning.contractConfirmationThreshold {
                    issues.append(ValidationIssue(
                        severity: .error,
                        code: .ambiguousFieldMapping,
                        stage: .dataContractValidation,
                        message: "\(manifest.displayName) 的表格结构置信度低于 \(AnalysisHarnessTrustTuning.contractConfirmationThreshold)，需要确认周期列、指标列和值列。",
                        expected: "结构置信度 >= \(AnalysisHarnessTrustTuning.contractConfirmationThreshold)",
                        actual: "\(understanding.confidence)"
                    ))
                } else if understanding.confidence < AnalysisHarnessTrustTuning.contractPassThreshold {
                    warnings.append("\(manifest.displayName) 表格结构置信度中等。")
                    issues.append(ValidationIssue(
                        severity: .warning,
                        code: .ambiguousFieldMapping,
                        stage: .dataContractValidation,
                        message: "\(manifest.displayName) 的表格结构置信度低于 \(AnalysisHarnessTrustTuning.contractPassThreshold)，本轮继续分析但保留风险提示。"
                    ))
                }
                if understanding.metricValueColumn != nil,
                   understanding.metricCatalog.isEmpty {
                    issues.append(ValidationIssue(
                        severity: .error,
                        code: .dataContractViolation,
                        stage: .dataContractValidation,
                        message: "\(manifest.displayName) 已识别数值列，但没有形成指标目录。"
                    ))
                }
            } else {
                let numericColumnCount = manifest.columns.filter { $0.aggregationRisk == .safeSum || $0.aggregationRisk == .safeAverage }.count
                if numericColumnCount == 0 {
                    issues.append(ValidationIssue(
                        severity: .warning,
                        code: .dataContractViolation,
                        stage: .dataContractValidation,
                        message: "\(manifest.displayName) 没有明显可计算数值列。"
                    ))
                }
            }
        }
        let status: DataContractValidationStatus
        if issues.contains(where: { $0.severity == .fatal }) {
            status = .blocked
        } else if issues.contains(where: { $0.severity == .error }) {
            status = .needsConfirmation
        } else if issues.contains(where: { $0.severity == .warning }) {
            status = .warning
        } else {
            status = .pass
        }
        let contractID = "\(manifests.map(\.id).joined(separator: "|").hashValue)-\(manifests.count)"
        let summary = DataContractValidationSummary(
            contractVersionID: contractID,
            status: status,
            checkedTableCount: manifests.count,
            confirmationThreshold: AnalysisHarnessTrustTuning.contractConfirmationThreshold,
            warningThreshold: AnalysisHarnessTrustTuning.contractPassThreshold,
            summary: "已按本地建议契约检查字段、时间范围和表格结构置信度。",
            warnings: warnings
        )
        return DataContractValidationOutput(summary: summary, issues: issues)
    }
}

enum RootCauseInvestigator {
    static func investigate(userQuery: String, results: [MetricResult], factTables: [NormalizedFactTable]) -> InvestigationRun? {
        let queryKey = userQuery.normalizedKey
        let shouldInvestigate = ["为什么", "原因", "归因", "影响", "驱动", "拆解"].contains { queryKey.contains($0.normalizedKey) }
        guard shouldInvestigate else { return nil }

        let dimensionFacts = factTables.flatMap(\.rows).filter { $0.dimensionName?.nilIfBlank != nil && $0.dimensionValue?.nilIfBlank != nil }
        if dimensionFacts.isEmpty {
            let steps = [
                RootCauseInvestigationStep(
                    order: 1,
                    title: "识别调查触发",
                    status: "completed",
                    detail: "用户问题包含原因/归因/驱动类意图。",
                    output: "进入根因候选调查，但只允许输出候选解释。",
                    confidence: 1
                ),
                RootCauseInvestigationStep(
                    order: 2,
                    title: "扫描可分解维度",
                    status: "blocked",
                    detail: "标准事实表中没有稳定的维度列和值。",
                    output: "无法执行渠道、场景、用户或产品分层贡献分解。",
                    confidence: 1
                ),
                RootCauseInvestigationStep(
                    order: 3,
                    title: "反证边界检查",
                    status: "not_available",
                    detail: "缺少维度事实和业务动作日志。",
                    output: "禁止输出高置信原因或因果表述。",
                    confidence: 1
                )
            ]
            return InvestigationRun(
                trigger: "用户问题触发",
                summary: "当前只输出候选原因边界；没有足够维度事实行支持贡献分解。",
                steps: steps,
                findings: [
                    InvestigationFinding(
                        kind: .cannotAttribute,
                        title: "缺少可验证维度",
                        detail: "当前事实表没有稳定的维度字段，无法把指标变化拆成渠道、场景、用户或产品贡献。",
                        evidenceLevel: "无法高置信归因",
                        limitations: ["缺少可验证维度字段", "贡献分解不可执行", "不能输出因果定论"]
                    )
                ],
                checkedCounterEvidence: ["已检查事实表维度字段"],
                missingCounterEvidence: ["渠道/场景/用户分层", "业务动作日志", "外部事件反证"]
            )
        }

        let total = dimensionFacts.compactMap(\.metricValue).map(abs).reduce(0, +)
        let grouped = Dictionary(grouping: dimensionFacts) { row in
            "\(row.dimensionName ?? "维度")=\(row.dimensionValue ?? "未命名")"
        }
        let contributionThreshold = AnalysisHarnessTrustTuning.contributionShareThreshold
        let findings = grouped.compactMap { key, rows -> InvestigationFinding? in
            let value = rows.compactMap(\.metricValue).reduce(0, +)
            let share = total > 0 ? abs(value) / total : nil
            guard let share, share >= contributionThreshold else {
                return InvestigationFinding(
                    kind: .weakSignal,
                    title: key,
                    detail: "贡献占比低于 \(Int(contributionThreshold * 100))%，不进入主原因排序。",
                    contributionValue: value,
                    contributionShare: share,
                    evidenceLevel: "弱信号",
                    limitations: ["贡献占比较低"]
                )
            }
            return InvestigationFinding(
                kind: .contributionBreakdown,
                title: key,
                detail: "该维度在当前可验证事实行中贡献较高，只能作为候选解释。",
                contributionValue: value,
                contributionShare: share,
                evidenceLevel: "候选",
                limitations: ["贡献分解不是因果检验", "需要业务动作和反证数据复核"]
            )
        }
        .sorted { ($0.contributionShare ?? 0) > ($1.contributionShare ?? 0) }

        let strongFindings = findings.filter { ($0.contributionShare ?? 0) >= contributionThreshold }
        let steps = [
            RootCauseInvestigationStep(
                order: 1,
                title: "识别调查触发",
                status: "completed",
                detail: "用户问题包含原因/归因/驱动类意图。",
                output: "进入多步骤候选调查。",
                confidence: 1
            ),
            RootCauseInvestigationStep(
                order: 2,
                title: "扫描可分解维度",
                status: "completed",
                detail: "扫描标准事实表中的维度列和值。",
                output: "发现 \(grouped.count) 个维度取值，覆盖 \(dimensionFacts.count) 行事实。",
                confidence: min(1, Double(dimensionFacts.count) / 50.0)
            ),
            RootCauseInvestigationStep(
                order: 3,
                title: "过滤弱信号",
                status: "completed",
                detail: "样本占比/贡献占比低于 \(Int(contributionThreshold * 100))% 的项不进入主原因排序。",
                output: "主候选 \(strongFindings.count) 个，弱信号 \(max(0, findings.count - strongFindings.count)) 个。",
                confidence: 0.86
            ),
            RootCauseInvestigationStep(
                order: 4,
                title: "执行贡献分解",
                status: total > 0 ? "completed" : "blocked",
                detail: "按维度事实值绝对贡献占比排序。",
                output: total > 0 ? "已生成候选贡献分解；边界为相关/贡献解释，非因果检验。" : "总贡献为 0，无法排序。",
                confidence: total > 0 ? 0.82 : 1
            ),
            RootCauseInvestigationStep(
                order: 5,
                title: "检查反证覆盖",
                status: "limited",
                detail: "检查当前本地事实是否包含业务动作、外部事件和 cohort 对照。",
                output: "当前缺少反证数据，禁止升级为高置信因果结论。",
                confidence: 1
            )
        ]

        return InvestigationRun(
            trigger: "用户问题触发",
            summary: "已按本地事实表做贡献分解；v1 不输出因果定论。",
            steps: steps,
            findings: findings,
            checkedCounterEvidence: ["已检查可用维度贡献"],
            missingCounterEvidence: ["外部事件窗口反证", "实验/策略变更日志", "用户 cohort 对照"]
        )
    }
}
