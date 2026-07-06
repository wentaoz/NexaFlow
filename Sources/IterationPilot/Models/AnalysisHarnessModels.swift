import Foundation

enum AnalysisHarnessValidationSeverity: String, Codable, CaseIterable, Identifiable, Hashable {
    case info
    case warning
    case error
    case fatal

    var id: String { rawValue }

    var label: String {
        switch self {
        case .info: return "信息"
        case .warning: return "警告"
        case .error: return "错误"
        case .fatal: return "阻断"
        }
    }

    var blocksOutput: Bool {
        self == .fatal || self == .error
    }
}

enum AnalysisHarnessStage: String, Codable, CaseIterable, Identifiable, Hashable {
    case manifestBuilding
    case dataContractValidation
    case tableUnderstanding
    case intentParsing
    case planGeneration
    case planValidation
    case planRepair
    case metricExecution
    case resultValidation
    case rootCauseInvestigation
    case contextEvidenceBuilding
    case contextEvidenceValidation
    case reportGeneration
    case reportValidation
    case answerNumberTracing
    case completed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .manifestBuilding: return "构建表画像"
        case .dataContractValidation: return "校验数据契约"
        case .tableUnderstanding: return "理解表格结构"
        case .intentParsing: return "解析分析意图"
        case .planGeneration: return "生成分析计划"
        case .planValidation: return "校验分析计划"
        case .planRepair: return "修复分析计划"
        case .metricExecution: return "执行本地指标"
        case .resultValidation: return "校验计算结果"
        case .rootCauseInvestigation: return "调查候选原因"
        case .contextEvidenceBuilding: return "构建资料证据"
        case .contextEvidenceValidation: return "校验证据引用"
        case .reportGeneration: return "生成解释报告"
        case .reportValidation: return "校验解释报告"
        case .answerNumberTracing: return "追溯回答数字"
        case .completed: return "完成 Harness"
        }
    }
}

enum AnalysisHarnessValidationCode: String, Codable, CaseIterable, Identifiable, Hashable {
    case schemaError = "SCHEMA_ERROR"
    case missingTable = "MISSING_TABLE"
    case missingField = "MISSING_FIELD"
    case unsupportedOperation = "UNSUPPORTED_OPERATION"
    case unsafeJoin = "UNSAFE_JOIN"
    case grainMismatch = "GRAIN_MISMATCH"
    case rateAggregationError = "RATE_AGGREGATION_ERROR"
    case missingAssumption = "MISSING_ASSUMPTION"
    case ambiguousFieldMapping = "AMBIGUOUS_FIELD_MAPPING"
    case distinctCountRisk = "DISTINCT_COUNT_RISK"
    case duplicateRecordRisk = "DUPLICATE_RECORD_RISK"
    case emptyResult = "EMPTY_RESULT"
    case formulaMismatch = "FORMULA_MISMATCH"
    case unverifiedNumber = "UNVERIFIED_NUMBER"
    case unverifiedClaim = "UNVERIFIED_CLAIM"
    case hiddenWarning = "HIDDEN_WARNING"
    case missingMethodology = "MISSING_METHODOLOGY"
    case placeholderOutput = "PLACEHOLDER_OUTPUT"
    case insufficientData = "INSUFFICIENT_DATA"
    case missingCitation = "MISSING_CITATION"
    case externalNumberMixedWithLocalMetric = "EXTERNAL_NUMBER_MIXED_WITH_LOCAL_METRIC"
    case evidenceBoundaryMissing = "EVIDENCE_BOUNDARY_MISSING"
    case ambiguousNumberTrace = "AMBIGUOUS_NUMBER_TRACE"
    case dataContractViolation = "DATA_CONTRACT_VIOLATION"
    case causalBoundaryRisk = "CAUSAL_BOUNDARY_RISK"
    case aiIntentParsingFailed = "AI_INTENT_PARSING_FAILED"

    var id: String { rawValue }
}

struct ValidationIssue: Identifiable, Codable, Hashable {
    var id: UUID
    var severity: AnalysisHarnessValidationSeverity
    var code: AnalysisHarnessValidationCode
    var stage: AnalysisHarnessStage
    var message: String
    var path: String
    var expected: String
    var actual: String
    var fixHint: String
    var evidence: [String: String]

    init(
        id: UUID = UUID(),
        severity: AnalysisHarnessValidationSeverity,
        code: AnalysisHarnessValidationCode,
        stage: AnalysisHarnessStage,
        message: String,
        path: String = "",
        expected: String = "",
        actual: String = "",
        fixHint: String = "",
        evidence: [String: String] = [:]
    ) {
        self.id = id
        self.severity = severity
        self.code = code
        self.stage = stage
        self.message = message
        self.path = path
        self.expected = expected
        self.actual = actual
        self.fixHint = fixHint
        self.evidence = evidence
    }
}

enum HarnessColumnInferredType: String, Codable, CaseIterable, Identifiable, Hashable {
    case string
    case number
    case integer
    case date
    case boolean
    case category
    case unknown

    var id: String { rawValue }
}

enum HarnessColumnSemanticRole: String, Codable, CaseIterable, Identifiable, Hashable {
    case objectID = "object_id"
    case recordID = "record_id"
    case date
    case period
    case metricName = "metric_name"
    case metricValue = "metric_value"
    case amount
    case quantity
    case rate
    case category
    case status
    case source
    case unknown

    var id: String { rawValue }
}

enum HarnessAggregationRisk: String, Codable, CaseIterable, Identifiable, Hashable {
    case safeSum = "safe_sum"
    case safeAverage = "safe_average"
    case rateLike = "rate_like"
    case idLike = "id_like"
    case categoryLike = "category_like"
    case unknown

    var id: String { rawValue }
}

struct HarnessSemanticCandidate: Codable, Hashable {
    var role: HarnessColumnSemanticRole
    var confidence: Double
    var reason: String
}

struct ColumnManifest: Identifiable, Codable, Hashable {
    var id: String { name }
    var name: String
    var inferredType: HarnessColumnInferredType
    var semanticCandidates: [HarnessSemanticCandidate]
    var aggregationRisk: HarnessAggregationRisk
    var nullCount: Int
    var nonNullCount: Int
    var uniqueCount: Int
    var sampleValues: [String]
    var numericMin: Double?
    var numericMax: Double?
    var dateMin: String?
    var dateMax: String?
}

enum HarnessTableGrainKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case oneRowPerRecord = "one_row_per_record"
    case oneRowPerPeriod = "one_row_per_period"
    case oneRowPerMetricPeriod = "one_row_per_metric_period"
    case pivotSummary = "pivot_summary"
    case aggregatedSummary = "aggregated_summary"
    case unknown

    var id: String { rawValue }
}

struct HarnessDetectedGrain: Codable, Hashable {
    var kind: HarnessTableGrainKind
    var confidence: Double
    var keyColumns: [String]
    var description: String
}

struct HarnessManifestDateRange: Codable, Hashable {
    var column: String
    var min: String
    var max: String
    var nonNullCount: Int
}

struct HarnessDuplicateSummary: Codable, Hashable {
    var exactDuplicateRowCount: Int
    var duplicateRatio: Double
    var candidateKeyColumns: [String]
}

enum HarnessTableUnderstandingShape: String, Codable, CaseIterable, Identifiable, Hashable {
    case standardWide = "standard_wide"
    case metricPeriodValue = "metric_period_value"
    case tableauLong = "tableau_long"
    case semiPivot = "semi_pivot"
    case horizontalPivot = "horizontal_pivot"
    case mixed = "mixed"
    case unknown

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standardWide: return "标准宽表"
        case .metricPeriodValue: return "指标-周期-值长表"
        case .tableauLong: return "Tableau 长表"
        case .semiPivot: return "半透视表"
        case .horizontalPivot: return "横向透视表"
        case .mixed: return "混合结构表"
        case .unknown: return "未确认"
        }
    }
}

enum HarnessMetricValueKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case additive
    case ratio
    case derived
    case text
    case unknown

    var id: String { rawValue }
}

struct HarnessMetricCatalogEntry: Identifiable, Codable, Hashable {
    var id: String { metricName.normalizedKey }
    var metricName: String
    var valueKind: HarnessMetricValueKind
    var observationCount: Int
    var firstPeriod: String?
    var lastPeriod: String?
    var sampleValues: [String]
}

struct HarnessSourceCellRef: Codable, Hashable {
    var sheetName: String
    var row: Int
    var column: Int
    var columnName: String
    var value: String

    var a1Address: String {
        "\(Self.columnLetters(column))\(row)"
    }

    private static func columnLetters(_ column: Int) -> String {
        guard column > 0 else { return "?" }
        var number = column
        var result = ""
        while number > 0 {
            let remainder = (number - 1) % 26
            guard let scalar = UnicodeScalar(65 + remainder) else { break }
            result = String(scalar) + result
            number = (number - 1) / 26
        }
        return result
    }
}

struct HarnessTableUnderstandingSummary: Codable, Hashable {
    var shape: HarnessTableUnderstandingShape
    var confidence: Double
    var periodColumn: String?
    var metricNameColumn: String?
    var metricValueColumn: String?
    var dimensionColumns: [String]
    var metricCatalog: [HarnessMetricCatalogEntry]
    var warnings: [String]
}

struct NormalizedFactRow: Identifiable, Codable, Hashable {
    var id: UUID
    var tableID: String
    var tableName: String
    var sourceSheet: String
    var sourceRow: Int
    var sourceColumn: Int
    var periodRaw: String
    var periodStart: String?
    var periodEnd: String?
    var periodBucket: String?
    var metricName: String
    var metricValue: Double?
    var rawValue: String
    var unit: String
    var valueKind: HarnessMetricValueKind
    var dimensionName: String?
    var dimensionValue: String?

    init(
        id: UUID = UUID(),
        tableID: String,
        tableName: String,
        sourceSheet: String,
        sourceRow: Int,
        sourceColumn: Int,
        periodRaw: String,
        periodStart: String?,
        periodEnd: String?,
        periodBucket: String?,
        metricName: String,
        metricValue: Double?,
        rawValue: String,
        unit: String = "",
        valueKind: HarnessMetricValueKind,
        dimensionName: String? = nil,
        dimensionValue: String? = nil
    ) {
        self.id = id
        self.tableID = tableID
        self.tableName = tableName
        self.sourceSheet = sourceSheet
        self.sourceRow = sourceRow
        self.sourceColumn = sourceColumn
        self.periodRaw = periodRaw
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.periodBucket = periodBucket
        self.metricName = metricName
        self.metricValue = metricValue
        self.rawValue = rawValue
        self.unit = unit
        self.valueKind = valueKind
        self.dimensionName = dimensionName
        self.dimensionValue = dimensionValue
    }

    var sourceCell: HarnessSourceCellRef {
        HarnessSourceCellRef(
            sheetName: sourceSheet,
            row: sourceRow,
            column: sourceColumn,
            columnName: "值",
            value: rawValue
        )
    }
}

struct NormalizedFactTable: Identifiable, Codable, Hashable {
    var id: UUID
    var tableID: String
    var tableName: String
    var shape: HarnessTableUnderstandingShape
    var confidence: Double
    var rows: [NormalizedFactRow]
    var metricCatalog: [HarnessMetricCatalogEntry]
    var metricAliases: [String: String] = [:]
    var warnings: [String]

    init(
        id: UUID = UUID(),
        tableID: String,
        tableName: String,
        shape: HarnessTableUnderstandingShape,
        confidence: Double,
        rows: [NormalizedFactRow],
        metricCatalog: [HarnessMetricCatalogEntry],
        metricAliases: [String: String] = [:],
        warnings: [String] = []
    ) {
        self.id = id
        self.tableID = tableID
        self.tableName = tableName
        self.shape = shape
        self.confidence = confidence
        self.rows = rows
        self.metricCatalog = metricCatalog
        self.metricAliases = metricAliases
        self.warnings = warnings
    }
}

struct TableManifest: Identifiable, Codable, Hashable {
    var id: String
    var reportID: UUID
    var displayName: String
    var rowCount: Int
    var columnCount: Int
    var sourceFormat: String
    var sourceType: String
    var shape: String
    var columns: [ColumnManifest]
    var detectedGrain: HarnessDetectedGrain
    var dateRanges: [HarnessManifestDateRange]
    var duplicateSummary: HarnessDuplicateSummary
    var warnings: [String]
    var understanding: HarnessTableUnderstandingSummary? = nil

    var metricNameColumn: ColumnManifest? {
        columns.max { lhs, rhs in
            lhs.confidence(for: .metricName) < rhs.confidence(for: .metricName)
        }.flatMap { $0.confidence(for: .metricName) > 0.45 ? $0 : nil }
    }

    var metricValueColumn: ColumnManifest? {
        columns.max { lhs, rhs in
            lhs.confidence(for: .metricValue) < rhs.confidence(for: .metricValue)
        }.flatMap { $0.confidence(for: .metricValue) > 0.45 ? $0 : nil }
    }

    var periodColumn: ColumnManifest? {
        columns.max { lhs, rhs in
            max(lhs.confidence(for: .period), lhs.confidence(for: .date)) < max(rhs.confidence(for: .period), rhs.confidence(for: .date))
        }.flatMap { max($0.confidence(for: .period), $0.confidence(for: .date)) > 0.45 ? $0 : nil }
    }
}

extension ColumnManifest {
    func confidence(for role: HarnessColumnSemanticRole) -> Double {
        semanticCandidates
            .filter { $0.role == role }
            .map(\.confidence)
            .max() ?? 0
    }
}

enum HarnessAnalysisOperation: String, Codable, CaseIterable, Identifiable, Hashable {
    case filter
    case groupBy = "group_by"
    case countRows = "count_rows"
    case countDistinct = "count_distinct"
    case sum
    case avg
    case min
    case max
    case dateTrunc = "date_trunc"
    case calculateRatio = "calculate_ratio"
    case calculateGrowthRate = "calculate_growth_rate"
    case calculateDifference = "calculate_difference"
    case append
    case leftJoin = "left_join"
    case innerJoin = "inner_join"

    var id: String { rawValue }
}

enum HarnessFilterOperator: String, Codable, CaseIterable, Identifiable, Hashable {
    case equals
    case notEquals = "not_equals"
    case contains
    case greaterThan = "greater_than"
    case greaterThanOrEqual = "greater_than_or_equal"
    case lessThan = "less_than"
    case lessThanOrEqual = "less_than_or_equal"
    case between
    case inList = "in"

    var id: String { rawValue }
}

struct HarnessFilterDefinition: Codable, Hashable {
    var field: String
    var op: HarnessFilterOperator
    var value: String
    var values: [String]

    init(field: String, op: HarnessFilterOperator, value: String = "", values: [String] = []) {
        self.field = field
        self.op = op
        self.value = value
        self.values = values
    }
}

struct AnalysisStep: Identifiable, Codable, Hashable {
    var id: UUID
    var operation: HarnessAnalysisOperation
    var tableID: String
    var field: String?
    var groupBy: [String]
    var filters: [HarnessFilterDefinition]
    var dependsOn: [UUID]
    var outputName: String
    var rationale: String

    init(
        id: UUID = UUID(),
        operation: HarnessAnalysisOperation,
        tableID: String,
        field: String? = nil,
        groupBy: [String] = [],
        filters: [HarnessFilterDefinition] = [],
        dependsOn: [UUID] = [],
        outputName: String,
        rationale: String = ""
    ) {
        self.id = id
        self.operation = operation
        self.tableID = tableID
        self.field = field
        self.groupBy = groupBy
        self.filters = filters
        self.dependsOn = dependsOn
        self.outputName = outputName
        self.rationale = rationale
    }
}

struct MetricDefinition: Identifiable, Codable, Hashable {
    var id: UUID
    var label: String
    var operation: HarnessAnalysisOperation
    var tableID: String
    var field: String?
    var groupBy: [String]
    var filters: [HarnessFilterDefinition]
    var numeratorMetricID: UUID?
    var denominatorMetricID: UUID?
    var baseMetricID: UUID?
    var comparisonMetricID: UUID?
    var unit: String
    var methodology: String
    var evidenceLevel: String

    init(
        id: UUID = UUID(),
        label: String,
        operation: HarnessAnalysisOperation,
        tableID: String,
        field: String? = nil,
        groupBy: [String] = [],
        filters: [HarnessFilterDefinition] = [],
        numeratorMetricID: UUID? = nil,
        denominatorMetricID: UUID? = nil,
        baseMetricID: UUID? = nil,
        comparisonMetricID: UUID? = nil,
        unit: String = "",
        methodology: String = "",
        evidenceLevel: String = "本地计算"
    ) {
        self.id = id
        self.label = label
        self.operation = operation
        self.tableID = tableID
        self.field = field
        self.groupBy = groupBy
        self.filters = filters
        self.numeratorMetricID = numeratorMetricID
        self.denominatorMetricID = denominatorMetricID
        self.baseMetricID = baseMetricID
        self.comparisonMetricID = comparisonMetricID
        self.unit = unit
        self.methodology = methodology
        self.evidenceLevel = evidenceLevel
    }
}

struct HarnessTableRelationship: Codable, Hashable {
    var leftTableID: String
    var rightTableID: String
    var leftKey: String
    var rightKey: String
    var joinType: HarnessAnalysisOperation
    var safeToJoin: Bool
    var reason: String
}

struct HarnessAnalysisAssumption: Codable, Hashable {
    var label: String
    var detail: String
    var affectsResult: Bool
}

struct AnalysisPlan: Identifiable, Codable, Hashable {
    var id: UUID
    var userQuestion: String
    var tablesUsed: [String]
    var steps: [AnalysisStep]
    var metrics: [MetricDefinition]
    var relationships: [HarnessTableRelationship]
    var assumptions: [HarnessAnalysisAssumption]
    var limitations: [String]
    var intendedOutput: String
    var createdBy: String

    init(
        id: UUID = UUID(),
        userQuestion: String,
        tablesUsed: [String],
        steps: [AnalysisStep] = [],
        metrics: [MetricDefinition],
        relationships: [HarnessTableRelationship] = [],
        assumptions: [HarnessAnalysisAssumption] = [],
        limitations: [String] = [],
        intendedOutput: String = "直接回答用户问题，并列出本地已验证指标。",
        createdBy: String = "local"
    ) {
        self.id = id
        self.userQuestion = userQuestion
        self.tablesUsed = tablesUsed
        self.steps = steps
        self.metrics = metrics
        self.relationships = relationships
        self.assumptions = assumptions
        self.limitations = limitations
        self.intendedOutput = intendedOutput
        self.createdBy = createdBy
    }
}

enum MetricResultFormat: String, Codable, CaseIterable, Identifiable, Hashable {
    case integer
    case decimal
    case percent
    case currency
    case text

    var id: String { rawValue }
}

enum MetricResultPresentationRole: String, Codable, CaseIterable, Identifiable, Hashable {
    case requested
    case derivedRequested = "derived_requested"
    case supporting
    case diagnostic

    var id: String { rawValue }

    var isPrimaryAnswerRole: Bool {
        self == .requested || self == .derivedRequested
    }
}

struct MetricResultSource: Codable, Hashable {
    var tableID: String
    var tableName: String
    var operation: HarnessAnalysisOperation
    var field: String?
    var groupKey: String
    var rowCount: Int
    var filtersApplied: [HarnessFilterDefinition]
    var methodology: String
    var factRowCount: Int? = nil
    var sourceRowRange: String? = nil
    var sourceColumnRange: String? = nil
    var sourceCells: [HarnessSourceCellRef]? = nil
    var coverageSummary: String? = nil
    var lineageSummary: String? = nil
}

struct MetricResult: Identifiable, Codable, Hashable {
    var id: UUID
    var metricID: UUID
    var label: String
    var rawValue: Double?
    var textValue: String?
    var unit: String
    var format: MetricResultFormat
    var source: MetricResultSource
    var confidence: Double
    var warnings: [String]
    var presentationRole: MetricResultPresentationRole

    init(
        id: UUID = UUID(),
        metricID: UUID,
        label: String,
        rawValue: Double?,
        textValue: String? = nil,
        unit: String = "",
        format: MetricResultFormat = .decimal,
        source: MetricResultSource,
        confidence: Double = 1,
        warnings: [String] = [],
        presentationRole: MetricResultPresentationRole = .requested
    ) {
        self.id = id
        self.metricID = metricID
        self.label = label
        self.rawValue = rawValue
        self.textValue = textValue
        self.unit = unit
        self.format = format
        self.source = source
        self.confidence = confidence
        self.warnings = warnings
        self.presentationRole = presentationRole
    }

    var displayValue: String {
        if let textValue, !textValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return textValue
        }
        guard let rawValue else { return "未覆盖" }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.groupingSize = 3
        formatter.maximumFractionDigits = maximumFractionDigits(for: rawValue)
        formatter.minimumFractionDigits = 0
        let numberText = formatter.string(from: NSNumber(value: rawValue)) ?? "\(rawValue)"
        switch format {
        case .percent:
            return "\(numberText)%"
        case .currency, .integer, .decimal, .text:
            return unit.isEmpty ? numberText : "\(numberText) \(unit)"
        }
    }

    private func maximumFractionDigits(for rawValue: Double) -> Int {
        switch format {
        case .integer:
            return 0
        case .percent:
            return 2
        case .currency:
            if unit.contains("/") { return 2 }
            return abs(rawValue.rounded() - rawValue) < 0.000001 ? 0 : 2
        case .decimal, .text:
            return 2
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case metricID
        case label
        case rawValue
        case textValue
        case unit
        case format
        case source
        case confidence
        case warnings
        case presentationRole
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        metricID = try container.decode(UUID.self, forKey: .metricID)
        label = try container.decode(String.self, forKey: .label)
        rawValue = try container.decodeIfPresent(Double.self, forKey: .rawValue)
        textValue = try container.decodeIfPresent(String.self, forKey: .textValue)
        unit = try container.decodeIfPresent(String.self, forKey: .unit) ?? ""
        format = try container.decodeIfPresent(MetricResultFormat.self, forKey: .format) ?? .decimal
        source = try container.decode(MetricResultSource.self, forKey: .source)
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence) ?? 1
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
        presentationRole = try container.decodeIfPresent(MetricResultPresentationRole.self, forKey: .presentationRole) ?? .requested
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(metricID, forKey: .metricID)
        try container.encode(label, forKey: .label)
        try container.encodeIfPresent(rawValue, forKey: .rawValue)
        try container.encodeIfPresent(textValue, forKey: .textValue)
        try container.encode(unit, forKey: .unit)
        try container.encode(format, forKey: .format)
        try container.encode(source, forKey: .source)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(warnings, forKey: .warnings)
        try container.encode(presentationRole, forKey: .presentationRole)
    }
}

enum AnswerNumberTraceStatus: String, Codable, CaseIterable, Identifiable, Hashable {
    case matched
    case approximateMatched = "approximate_matched"
    case ambiguous
    case unmatched
    case ignored

    var id: String { rawValue }

    var label: String {
        switch self {
        case .matched: return "已追溯"
        case .approximateMatched: return "近似追溯"
        case .ambiguous: return "多候选歧义"
        case .unmatched: return "未追溯"
        case .ignored: return "已忽略"
        }
    }
}

struct AnswerNumberTrace: Identifiable, Codable, Hashable {
    var id: UUID
    var rawText: String
    var normalizedValue: Double?
    var unitHint: String
    var contextSnippet: String
    var status: AnswerNumberTraceStatus
    var matchedResultID: UUID?
    var matchedResultLabel: String?
    var toleranceDescription: String
    var candidateLabels: [String]
    var candidateResultIDs: [UUID]
    var reason: String

    init(
        id: UUID = UUID(),
        rawText: String,
        normalizedValue: Double?,
        unitHint: String = "",
        contextSnippet: String = "",
        status: AnswerNumberTraceStatus,
        matchedResultID: UUID? = nil,
        matchedResultLabel: String? = nil,
        toleranceDescription: String = "",
        candidateLabels: [String] = [],
        candidateResultIDs: [UUID] = [],
        reason: String = ""
    ) {
        self.id = id
        self.rawText = rawText
        self.normalizedValue = normalizedValue
        self.unitHint = unitHint
        self.contextSnippet = contextSnippet
        self.status = status
        self.matchedResultID = matchedResultID
        self.matchedResultLabel = matchedResultLabel
        self.toleranceDescription = toleranceDescription
        self.candidateLabels = candidateLabels
        self.candidateResultIDs = candidateResultIDs
        self.reason = reason
    }
}

struct TableStructureConfirmationDraft: Identifiable, Codable, Hashable {
    var id: UUID
    var sessionID: UUID?
    var reportID: UUID
    var reportName: String
    var confidence: Double
    var reason: String
    var periodColumnCandidates: [String]
    var metricNameColumnCandidates: [String]
    var metricValueColumnCandidates: [String]
    var selectedPeriodColumn: String?
    var selectedMetricNameColumn: String?
    var selectedMetricValueColumn: String?
    var fillDownPeriod: Bool
    var halfYearBucketRule: String

    init(
        id: UUID = UUID(),
        sessionID: UUID? = nil,
        reportID: UUID,
        reportName: String,
        confidence: Double,
        reason: String,
        periodColumnCandidates: [String],
        metricNameColumnCandidates: [String],
        metricValueColumnCandidates: [String],
        selectedPeriodColumn: String? = nil,
        selectedMetricNameColumn: String? = nil,
        selectedMetricValueColumn: String? = nil,
        fillDownPeriod: Bool = true,
        halfYearBucketRule: String = "period_start_date"
    ) {
        self.id = id
        self.sessionID = sessionID
        self.reportID = reportID
        self.reportName = reportName
        self.confidence = confidence
        self.reason = reason
        self.periodColumnCandidates = periodColumnCandidates
        self.metricNameColumnCandidates = metricNameColumnCandidates
        self.metricValueColumnCandidates = metricValueColumnCandidates
        self.selectedPeriodColumn = selectedPeriodColumn
        self.selectedMetricNameColumn = selectedMetricNameColumn
        self.selectedMetricValueColumn = selectedMetricValueColumn
        self.fillDownPeriod = fillDownPeriod
        self.halfYearBucketRule = halfYearBucketRule
    }
}

struct MetricMappingCandidate: Identifiable, Codable, Hashable {
    var id: String { actualMetric.normalizedKey }
    var actualMetric: String
    var score: Double
    var sampleValues: [String]
}

struct MetricMappingConfirmationDraft: Identifiable, Codable, Hashable {
    var id: UUID
    var sessionID: UUID?
    var reportID: UUID
    var reportName: String
    var requestedMetric: String
    var candidates: [MetricMappingCandidate]
    var selectedActualMetric: String?
    var saveAsTemplate: Bool

    init(
        id: UUID = UUID(),
        sessionID: UUID? = nil,
        reportID: UUID,
        reportName: String,
        requestedMetric: String,
        candidates: [MetricMappingCandidate],
        selectedActualMetric: String? = nil,
        saveAsTemplate: Bool = true
    ) {
        self.id = id
        self.sessionID = sessionID
        self.reportID = reportID
        self.reportName = reportName
        self.requestedMetric = requestedMetric
        self.candidates = candidates
        self.selectedActualMetric = selectedActualMetric
        self.saveAsTemplate = saveAsTemplate
    }
}

enum DataContractValidationStatus: String, Codable, CaseIterable, Identifiable, Hashable {
    case pass
    case warning
    case needsConfirmation = "needs_confirmation"
    case blocked

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pass: return "通过"
        case .warning: return "有警告"
        case .needsConfirmation: return "需确认"
        case .blocked: return "已阻断"
        }
    }
}

struct DataContractValidationSummary: Codable, Hashable {
    var contractVersionID: String
    var status: DataContractValidationStatus
    var checkedTableCount: Int
    var confirmationThreshold: Double
    var warningThreshold: Double
    var summary: String
    var warnings: [String]
}

enum InvestigationFindingKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case candidateReason = "candidate_reason"
    case contributionBreakdown = "contribution_breakdown"
    case weakSignal = "weak_signal"
    case cannotAttribute = "cannot_attribute"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .candidateReason: return "候选原因"
        case .contributionBreakdown: return "贡献分解"
        case .weakSignal: return "弱信号"
        case .cannotAttribute: return "无法高置信归因"
        }
    }
}

struct InvestigationFinding: Identifiable, Codable, Hashable {
    var id: UUID
    var kind: InvestigationFindingKind
    var title: String
    var detail: String
    var contributionValue: Double?
    var contributionShare: Double?
    var evidenceLevel: String
    var limitations: [String]

    init(
        id: UUID = UUID(),
        kind: InvestigationFindingKind,
        title: String,
        detail: String,
        contributionValue: Double? = nil,
        contributionShare: Double? = nil,
        evidenceLevel: String = "候选",
        limitations: [String] = []
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.contributionValue = contributionValue
        self.contributionShare = contributionShare
        self.evidenceLevel = evidenceLevel
        self.limitations = limitations
    }
}

struct InvestigationRun: Identifiable, Codable, Hashable {
    var id: UUID
    var createdAt: Date
    var trigger: String
    var summary: String
    var steps: [RootCauseInvestigationStep]
    var findings: [InvestigationFinding]
    var checkedCounterEvidence: [String]
    var missingCounterEvidence: [String]

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        trigger: String,
        summary: String,
        steps: [RootCauseInvestigationStep] = [],
        findings: [InvestigationFinding],
        checkedCounterEvidence: [String] = [],
        missingCounterEvidence: [String] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.trigger = trigger
        self.summary = summary
        self.steps = steps
        self.findings = findings
        self.checkedCounterEvidence = checkedCounterEvidence
        self.missingCounterEvidence = missingCounterEvidence
    }
}

struct RootCauseInvestigationStep: Identifiable, Codable, Hashable {
    var id: UUID
    var order: Int
    var title: String
    var status: String
    var detail: String
    var output: String
    var confidence: Double

    init(
        id: UUID = UUID(),
        order: Int,
        title: String,
        status: String,
        detail: String,
        output: String,
        confidence: Double
    ) {
        self.id = id
        self.order = order
        self.title = title
        self.status = status
        self.detail = detail
        self.output = output
        self.confidence = confidence
    }
}

enum ContextEvidenceSourceType: String, Codable, CaseIterable, Identifiable, Hashable {
    case correctionMemory = "correction_memory"
    case reportKnowledge = "report_knowledge"
    case knowledgeBase = "knowledge_base"
    case confluence
    case jira
    case dingtalk
    case externalReference = "external_reference"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .correctionMemory: return "纠偏记忆"
        case .reportKnowledge: return "报表知识"
        case .knowledgeBase: return "知识库"
        case .confluence: return "Confluence"
        case .jira: return "Jira"
        case .dingtalk: return "钉钉"
        case .externalReference: return "外部参照"
        }
    }
}

enum ContextEvidenceConfidence: String, Codable, CaseIterable, Identifiable, Hashable {
    case high
    case medium
    case low

    var id: String { rawValue }

    var label: String {
        switch self {
        case .high: return "高"
        case .medium: return "中"
        case .low: return "低"
        }
    }
}

struct ContextEvidenceItem: Identifiable, Codable, Hashable {
    var id: UUID
    var sourceType: ContextEvidenceSourceType
    var sourceID: String
    var title: String
    var summary: String
    var citationLabel: String
    var sourceURL: String?
    var eventDate: Date?
    var confidence: ContextEvidenceConfidence
    var limitations: [String]

    init(
        id: UUID = UUID(),
        sourceType: ContextEvidenceSourceType,
        sourceID: String,
        title: String,
        summary: String,
        citationLabel: String,
        sourceURL: String? = nil,
        eventDate: Date? = nil,
        confidence: ContextEvidenceConfidence = .medium,
        limitations: [String] = []
    ) {
        self.id = id
        self.sourceType = sourceType
        self.sourceID = sourceID
        self.title = title
        self.summary = summary
        self.citationLabel = citationLabel
        self.sourceURL = sourceURL
        self.eventDate = eventDate
        self.confidence = confidence
        self.limitations = limitations
    }
}

struct ContextEvidenceManifest: Identifiable, Codable, Hashable {
    var id: UUID
    var sourcePolicy: AnalysisContextSourcePolicy
    var items: [ContextEvidenceItem]
    var warnings: [String]

    init(
        id: UUID = UUID(),
        sourcePolicy: AnalysisContextSourcePolicy,
        items: [ContextEvidenceItem],
        warnings: [String] = []
    ) {
        self.id = id
        self.sourcePolicy = sourcePolicy
        self.items = items
        self.warnings = warnings
    }

    var evidenceMarkdown: String {
        let itemLines = items.map { item in
            let url = item.sourceURL.flatMap(\.nilIfBlank).map { "；URL：\($0)" } ?? ""
            let limits = item.limitations.isEmpty ? "" : "；限制：\(item.limitations.joined(separator: "、"))"
            return "- [\(item.citationLabel)] \(item.sourceType.label)：\(item.title)；置信度：\(item.confidence.label)；摘要：\(item.summary)\(url)\(limits)"
        }.joined(separator: "\n")
        let warningLines = warnings.map { "- \($0)" }.joined(separator: "\n")
        return """
        ## Context Evidence Manifest
        - 资料范围：\(sourcePolicy.label)
        - 证据条目：\(items.count)

        ### Evidence Items
        \(itemLines.isEmpty ? "- 本轮未启用或未命中知识库/外部资料。" : itemLines)

        ### Evidence Warnings
        \(warningLines.isEmpty ? "- 无。" : warningLines)
        """
    }
}

enum AnalysisHarnessStatus: String, Codable, CaseIterable, Identifiable, Hashable {
    case success
    case successWithWarnings = "success_with_warnings"
    case blocked
    case failed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .success: return "已完成"
        case .successWithWarnings: return "已完成，有警告"
        case .blocked: return "已阻断"
        case .failed: return "基础设施失败"
        }
    }
}

enum AuditEventStatus: String, Codable, CaseIterable, Identifiable, Hashable {
    case started
    case completed
    case warning
    case failed

    var id: String { rawValue }

    var jobStatus: AIJobStatus {
        switch self {
        case .started: return .requesting
        case .completed: return .completed
        case .warning: return .validating
        case .failed: return .needsUserAction
        }
    }
}

struct AuditEvent: Identifiable, Codable, Hashable {
    var id: UUID
    var createdAt: Date
    var stage: AnalysisHarnessStage
    var status: AuditEventStatus
    var summary: String
    var details: [String: String]
    var durationMilliseconds: Int?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        stage: AnalysisHarnessStage,
        status: AuditEventStatus,
        summary: String,
        details: [String: String] = [:],
        durationMilliseconds: Int? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.stage = stage
        self.status = status
        self.summary = summary
        self.details = details
        self.durationMilliseconds = durationMilliseconds
    }
}

struct BlockedAnalysisOutput: Codable, Hashable {
    var title: String
    var reason: String
    var issues: [ValidationIssue]
    var nextSteps: [String]

    var markdown: String {
        let issueLines = issues.map { issue in
            let hint = issue.fixHint.nilIfBlank.map { " 建议：\($0)" } ?? ""
            return "- \(issue.message)\(hint)"
        }.joined(separator: "\n")
        let stepLines = nextSteps.map { "- \($0)" }.joined(separator: "\n")
        return """
        ## 直接回答你的问题
        这次分析暂时不能输出已校验数字：\(reason)

        ## 需要处理的问题
        \(issueLines.isEmpty ? "- 未返回具体问题。" : issueLines)

        ## 下一步
        \(stepLines.isEmpty ? "- 请补充字段、周期或调整选表后重试。" : stepLines)

        ## AI 读取到的数据
        本轮不会输出未经验证的业务结论。已读取当前任务选表和本地计算证据，但还需要确认表格结构、指标映射或补充缺失字段。内部校验代码可在“分析资料 > 证据 > 高级审计”中查看。
        """
    }
}

struct AnalysisHarnessRun: Identifiable, Codable, Hashable {
    var id: UUID
    var createdAt: Date
    var finishedAt: Date?
    var status: AnalysisHarnessStatus
    var userQuery: String
    var tableManifest: [TableManifest]
    var normalizedFactTables: [NormalizedFactTable] = []
    var contextEvidenceManifest: ContextEvidenceManifest?
    var analysisPlan: AnalysisPlan?
    var verifiedResults: [MetricResult]
    var validationIssues: [ValidationIssue]
    var auditLog: [AuditEvent]
    var reportMarkdown: String
    var repairAttemptsPlan: Int
    var repairAttemptsReport: Int
    var durationMilliseconds: Int
    var answerNumberTraces: [AnswerNumberTrace]?
    var dataContractSummary: DataContractValidationSummary?
    var investigationRun: InvestigationRun?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        finishedAt: Date? = nil,
        status: AnalysisHarnessStatus,
        userQuery: String,
        tableManifest: [TableManifest],
        normalizedFactTables: [NormalizedFactTable] = [],
        contextEvidenceManifest: ContextEvidenceManifest? = nil,
        analysisPlan: AnalysisPlan?,
        verifiedResults: [MetricResult],
        validationIssues: [ValidationIssue],
        auditLog: [AuditEvent],
        reportMarkdown: String,
        repairAttemptsPlan: Int,
        repairAttemptsReport: Int,
        durationMilliseconds: Int,
        answerNumberTraces: [AnswerNumberTrace]? = nil,
        dataContractSummary: DataContractValidationSummary? = nil,
        investigationRun: InvestigationRun? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.finishedAt = finishedAt
        self.status = status
        self.userQuery = userQuery
        self.tableManifest = tableManifest
        self.normalizedFactTables = normalizedFactTables
        self.contextEvidenceManifest = contextEvidenceManifest
        self.analysisPlan = analysisPlan
        self.verifiedResults = verifiedResults
        self.validationIssues = validationIssues
        self.auditLog = auditLog
        self.reportMarkdown = reportMarkdown
        self.repairAttemptsPlan = repairAttemptsPlan
        self.repairAttemptsReport = repairAttemptsReport
        self.durationMilliseconds = durationMilliseconds
        self.answerNumberTraces = answerNumberTraces
        self.dataContractSummary = dataContractSummary
        self.investigationRun = investigationRun
    }

    var hasBlockingIssue: Bool {
        validationIssues.contains { $0.severity.blocksOutput }
    }

    var evidenceMarkdown: String {
        let manifestLines = tableManifest.map { table in
            "- \(table.displayName)：\(table.rowCount) 行 × \(table.columnCount) 列；粒度：\(table.detectedGrain.kind.rawValue)；字段：\(table.columns.map(\.name).joined(separator: "、"))"
        }.joined(separator: "\n")
        let understandingLines = tableManifest.map { table in
            guard let understanding = table.understanding else {
                return "- \(table.displayName)：未生成表格理解。"
            }
            let columns = [
                understanding.periodColumn.map { "周期列=\($0)" },
                understanding.metricNameColumn.map { "指标列=\($0)" },
                understanding.metricValueColumn.map { "数值列=\($0)" }
            ].compactMap { $0 }.joined(separator: "；")
            let catalog = understanding.metricCatalog
                .prefix(8)
                .map { "\($0.metricName)(\($0.observationCount))" }
                .joined(separator: "、")
            return "- \(table.displayName)：\(understanding.shape.label)，置信度 \(Int(understanding.confidence * 100))%；\(columns.isEmpty ? "列映射未确认" : columns)；指标：\(catalog.isEmpty ? "未识别" : catalog)"
        }.joined(separator: "\n")
        let factPreviewLines = normalizedFactTables.flatMap { table in
            table.rows.prefix(8).map { row in
                let bucket = row.periodBucket.map { "；归属 \($0)" } ?? ""
                return "- \(table.tableName) R\(row.sourceRow)C\(row.sourceColumn)：\(row.periodRaw)\(bucket)；\(row.metricName)=\(row.rawValue)"
            }
        }.prefix(24).joined(separator: "\n")
        let planLines = analysisPlan?.metrics.map { metric in
            "- \(metric.label)：\(metric.operation.rawValue)，表 \(metric.tableID)，字段 \(metric.field ?? "-")"
        }.joined(separator: "\n") ?? "- 未生成可执行计划。"
        let resultLines = verifiedResults.map { result in
            let lineage = result.source.lineageSummary.map { "；来源：\($0)" } ?? ""
            return "- \(result.label)：\(result.displayValue)；\(result.source.methodology)\(lineage)"
        }.joined(separator: "\n")
        let keyResultLines = verifiedResults.map { result in
            let cells = (result.source.sourceCells ?? [])
                .prefix(4)
                .map { "\($0.sheetName)!\($0.a1Address)=\($0.value)" }
                .joined(separator: "；")
            let source = cells.isEmpty ? (result.source.lineageSummary ?? result.source.methodology) : cells
            return "- \(result.label)：\(result.displayValue)；\(source)"
        }.joined(separator: "\n")
        let factLines = normalizedFactTables.map { table in
            "- \(table.tableName)：\(table.shape.label)，事实行 \(table.rows.count)，指标 \(table.metricCatalog.map(\.metricName).prefix(12).joined(separator: "、"))"
        }.joined(separator: "\n")
        let numberTraceLines = (answerNumberTraces ?? []).map { trace in
            let candidates = trace.candidateLabels.isEmpty ? "" : "；候选：\(trace.candidateLabels.prefix(4).joined(separator: "、"))"
            let match = trace.matchedResultLabel.map { "；匹配：\($0)" } ?? ""
            return "- \(trace.rawText)：\(trace.status.label)\(match)；容差：\(trace.toleranceDescription)\(candidates)；上下文：\(trace.contextSnippet)"
        }.joined(separator: "\n")
        let contractLines: String
        if let dataContractSummary {
            let warnings = dataContractSummary.warnings.isEmpty ? "无" : dataContractSummary.warnings.joined(separator: "；")
            contractLines = """
            - 状态：\(dataContractSummary.status.label)
            - 契约版本：\(dataContractSummary.contractVersionID)
            - 表数量：\(dataContractSummary.checkedTableCount)
            - 阈值：确认 < \(dataContractSummary.confirmationThreshold)，通过 >= \(dataContractSummary.warningThreshold)
            - 摘要：\(dataContractSummary.summary)
            - 警告：\(warnings)
            """
        } else {
            contractLines = "- 本轮未生成数据契约摘要。"
        }
        let investigationLines: String
        if let investigationRun {
            let stepLines = investigationRun.steps.map { step in
                "- \(step.order). \(step.title)：\(step.detail)；状态：\(step.status)\(step.output.isEmpty ? "" : "；输出：\(step.output)")"
            }.joined(separator: "\n")
            let findings = investigationRun.findings.map { finding in
                let share = finding.contributionShare.map { "；贡献占比 \(String(format: "%.1f", $0 * 100))%" } ?? ""
                let limits = finding.limitations.isEmpty ? "" : "；限制：\(finding.limitations.joined(separator: "、"))"
                return "- [\(finding.kind.label)] \(finding.title)：\(finding.detail)\(share)；证据：\(finding.evidenceLevel)\(limits)"
            }.joined(separator: "\n")
            investigationLines = """
            - 触发：\(investigationRun.trigger)
            - 说明：\(investigationRun.summary)
            - 边界：贡献分解，非因果检验。
            \(stepLines.isEmpty ? "- 未记录调查步骤。" : stepLines)
            \(findings.isEmpty ? "- 未产出候选原因。" : findings)
            - 已检查反证：\(investigationRun.checkedCounterEvidence.isEmpty ? "无" : investigationRun.checkedCounterEvidence.joined(separator: "、"))
            - 未覆盖反证：\(investigationRun.missingCounterEvidence.isEmpty ? "无" : investigationRun.missingCounterEvidence.joined(separator: "、"))
            """
        } else {
            investigationLines = "- 本轮未触发根因调查。"
        }
        let contextEvidence = contextEvidenceManifest?.evidenceMarkdown ?? "本轮未启用资料证据 Harness。"
        let issueLines = validationIssues.map { issue in
            "- \(issue.severity.label) \(issue.code.rawValue)：\(issue.message)"
        }.joined(separator: "\n")
        let auditLines = auditLog.map { event in
            "- \(event.stage.label)：\(event.summary)"
        }.joined(separator: "\n")
        return """
        # Analysis Harness 审计

        ## 运行状态
        - Run ID：\(id.uuidString)
        - 状态：\(status.label)
        - 计划修复次数：\(repairAttemptsPlan)
        - 报告修复次数：\(repairAttemptsReport)
        - 耗时：\(durationMilliseconds) ms

        ## Table Manifest
        \(manifestLines.isEmpty ? "- 未读取到表。" : manifestLines)

        ## 表格理解
        \(understandingLines.isEmpty ? "- 未生成表格理解。" : understandingLines)

        ## 数据契约校验
        \(contractLines)

        ## Table Understanding / Normalized Facts
        \(factLines.isEmpty ? "- 未生成标准事实表。" : factLines)

        ## 标准事实表预览
        \(factPreviewLines.isEmpty ? "- 未生成事实行预览。" : factPreviewLines)

        ## Analysis Plan
        \(planLines)

        ## 关键指标结果
        \(keyResultLines.isEmpty ? "- 未产生关键指标结果。" : keyResultLines)

        ## 回答数字血缘
        \(numberTraceLines.isEmpty ? "- 暂无回答数字追溯记录。" : numberTraceLines)

        ## 根因调查
        \(investigationLines)

        ## Verified Results
        \(resultLines.isEmpty ? "- 未产生已验证结果。" : resultLines)

        ## Context Evidence
        \(contextEvidence)

        ## Validation Issues
        \(issueLines.isEmpty ? "- 无阻断或警告。" : issueLines)

        ## Audit Events
        \(auditLines.isEmpty ? "- 无审计事件。" : auditLines)
        """
    }
}
