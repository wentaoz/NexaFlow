import Foundation

struct MetricExecutor {
    static func execute(plan: AnalysisPlan, reports: [ImportedReport], manifests: [TableManifest]) -> [MetricResult] {
        let reportsByID = Dictionary(uniqueKeysWithValues: reports.map { ($0.id.uuidString, $0) })
        let manifestsByID = Dictionary(uniqueKeysWithValues: manifests.map { ($0.id, $0) })
        var results: [MetricResult] = []

        for metric in plan.metrics {
            if let derived = executeDerived(metric: metric, existingResults: results) {
                results.append(derived)
                continue
            }
            guard let report = reportsByID[metric.tableID],
                  let manifest = manifestsByID[metric.tableID] else {
                continue
            }
            let filteredRows = report.harnessRows.filter { row in
                metric.filters.allSatisfy { HarnessValueParser.matches(row[$0.field] ?? "", filter: $0) }
            }
            if metric.groupBy.isEmpty {
                results.append(executeSingleMetric(metric: metric, rows: filteredRows, manifest: manifest))
            } else {
                let grouped = Dictionary(grouping: filteredRows) { row in
                    metric.groupBy.map { "\($0)=\(row[$0] ?? "")" }.joined(separator: " · ")
                }
                for key in grouped.keys.sorted() {
                    var groupedMetric = metric
                    groupedMetric.label = "\(metric.label)（\(key.isEmpty ? "空值" : key)）"
                    results.append(executeSingleMetric(metric: groupedMetric, rows: grouped[key] ?? [], manifest: manifest, groupKey: key))
                }
            }
        }
        return results
    }

    private static func executeSingleMetric(
        metric: MetricDefinition,
        rows: [[String: String]],
        manifest: TableManifest,
        groupKey: String = ""
    ) -> MetricResult {
        let values = metric.field.map { field in rows.compactMap { HarnessValueParser.number(from: $0[field] ?? "") } } ?? []
        let rawValue: Double?
        let format: MetricResultFormat
        switch metric.operation {
        case .countRows:
            rawValue = Double(rows.count)
            format = .integer
        case .countDistinct:
            if let field = metric.field {
                rawValue = Double(Set(rows.map { ($0[field] ?? "").normalizedKey }.filter { !$0.isEmpty }).count)
            } else {
                rawValue = nil
            }
            format = .integer
        case .sum:
            rawValue = values.reduce(0, +)
            format = resultFormat(for: metric)
        case .avg:
            rawValue = values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
            format = metric.unit == "%" ? .percent : .decimal
        case .min:
            rawValue = values.min()
            format = resultFormat(for: metric)
        case .max:
            rawValue = values.max()
            format = resultFormat(for: metric)
        default:
            rawValue = nil
            format = .text
        }
        let source = MetricResultSource(
            tableID: manifest.id,
            tableName: manifest.displayName,
            operation: metric.operation,
            field: metric.field,
            groupKey: groupKey,
            rowCount: rows.count,
            filtersApplied: metric.filters,
            methodology: metric.methodology.nilIfBlank ?? defaultMethodology(metric: metric)
        )
        var warnings: [String] = []
        if rows.isEmpty {
            warnings.append("过滤后没有匹配行。")
        }
        if let field = metric.field, values.isEmpty, [.sum, .avg, .min, .max].contains(metric.operation) {
            warnings.append("字段 \(field) 没有可解析数值。")
        }
        return MetricResult(
            metricID: metric.id,
            label: metric.label,
            rawValue: rawValue,
            unit: metric.unit,
            format: format,
            source: source,
            confidence: warnings.isEmpty ? 1 : 0.65,
            warnings: warnings
        )
    }

    private static func executeDerived(metric: MetricDefinition, existingResults: [MetricResult]) -> MetricResult? {
        let resultsByMetricID = Dictionary(grouping: existingResults, by: \.metricID)
        let source = MetricResultSource(
            tableID: metric.tableID,
            tableName: "派生指标",
            operation: metric.operation,
            field: nil,
            groupKey: "",
            rowCount: 0,
            filtersApplied: metric.filters,
            methodology: metric.methodology.nilIfBlank ?? defaultMethodology(metric: metric)
        )
        func unresolvedResult(_ warnings: [String]) -> MetricResult {
            MetricResult(
                metricID: metric.id,
                label: metric.label,
                rawValue: nil,
                unit: metric.unit,
                format: resultFormat(for: metric),
                source: source,
                confidence: 0.2,
                warnings: warnings.isEmpty ? ["派生指标缺少可验证分子/分母或对比期结果。"] : warnings
            )
        }
        func scalarValue(for id: UUID, role: String) -> (value: Double?, warnings: [String]) {
            let matches = resultsByMetricID[id] ?? []
            let values = matches.compactMap(\.rawValue)
            if values.count == 1 {
                return (values[0], [])
            }
            if values.isEmpty {
                return (nil, ["\(role) 没有可用的已验证数值。"])
            }
            let labels = matches.prefix(4).map(\.label).joined(separator: "、")
            return (
                nil,
                ["\(role) 匹配到 \(values.count) 个分组结果，派生指标需要明确分组口径或先生成全周期汇总。示例结果：\(labels)。"]
            )
        }
        switch metric.operation {
        case .calculateRatio:
            guard let numeratorID = metric.numeratorMetricID,
                  let denominatorID = metric.denominatorMetricID else {
                return unresolvedResult(["派生比例缺少 numeratorMetricID 或 denominatorMetricID。"])
            }
            let numeratorLookup = scalarValue(for: numeratorID, role: "分子")
            let denominatorLookup = scalarValue(for: denominatorID, role: "分母")
            let lookupWarnings = numeratorLookup.warnings + denominatorLookup.warnings
            guard let numerator = numeratorLookup.value,
                  let denominator = denominatorLookup.value else {
                return unresolvedResult(lookupWarnings)
            }
            guard denominator != 0 else {
                return unresolvedResult(["分母为 0，无法计算比例。"])
            }
            return MetricResult(
                metricID: metric.id,
                label: metric.label,
                rawValue: numerator / denominator,
                unit: metric.unit,
                format: metric.unit == "%" ? .percent : .decimal,
                source: source,
                confidence: 1
            )
        case .calculateGrowthRate:
            guard let baseID = metric.baseMetricID,
                  let comparisonID = metric.comparisonMetricID else {
                return unresolvedResult(["增长率缺少 baseMetricID 或 comparisonMetricID。"])
            }
            let baseLookup = scalarValue(for: baseID, role: "基期")
            let comparisonLookup = scalarValue(for: comparisonID, role: "对比期")
            let lookupWarnings = baseLookup.warnings + comparisonLookup.warnings
            guard let base = baseLookup.value,
                  let comparison = comparisonLookup.value else {
                return unresolvedResult(lookupWarnings)
            }
            guard base != 0 else {
                return unresolvedResult(["基期为 0，无法计算增长率。"])
            }
            return MetricResult(
                metricID: metric.id,
                label: metric.label,
                rawValue: (comparison - base) / abs(base) * 100,
                unit: "%",
                format: .percent,
                source: source,
                confidence: 1
            )
        case .calculateDifference:
            guard let baseID = metric.baseMetricID,
                  let comparisonID = metric.comparisonMetricID else {
                return unresolvedResult(["差值计算缺少 baseMetricID 或 comparisonMetricID。"])
            }
            let baseLookup = scalarValue(for: baseID, role: "基期")
            let comparisonLookup = scalarValue(for: comparisonID, role: "对比期")
            let lookupWarnings = baseLookup.warnings + comparisonLookup.warnings
            guard let base = baseLookup.value,
                  let comparison = comparisonLookup.value else {
                return unresolvedResult(lookupWarnings)
            }
            return MetricResult(
                metricID: metric.id,
                label: metric.label,
                rawValue: comparison - base,
                unit: metric.unit,
                format: resultFormat(for: metric),
                source: source,
                confidence: 1
            )
        default:
            return nil
        }
    }

    private static func resultFormat(for metric: MetricDefinition) -> MetricResultFormat {
        let unitKey = metric.unit.normalizedKey
        if unitKey == "%" { return .percent }
        if unitKey.contains("mxn") || unitKey.contains("¥") || unitKey.contains("$") { return .currency }
        if unitKey.contains("人") || unitKey.contains("笔") { return .integer }
        return .decimal
    }

    private static func defaultMethodology(metric: MetricDefinition) -> String {
        switch metric.operation {
        case .sum: return "对 \(metric.field ?? "-") 执行 SUM。"
        case .avg: return "对 \(metric.field ?? "-") 执行 AVG。"
        case .countRows: return "统计匹配行数。"
        case .countDistinct: return "对 \(metric.field ?? "-") 执行 COUNT DISTINCT。"
        case .min: return "取 \(metric.field ?? "-") 最小值。"
        case .max: return "取 \(metric.field ?? "-") 最大值。"
        case .calculateRatio: return "用已验证分子/分母重算比例。"
        case .calculateGrowthRate: return "用已验证基期和对比期重算增长率。"
        case .calculateDifference: return "用已验证对比期减基期。"
        default: return "执行本地指标计算。"
        }
    }
}

struct ResultValidator {
    static func validate(results: [MetricResult], plan: AnalysisPlan, manifests: [TableManifest]) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if results.isEmpty {
            issues.append(ValidationIssue(
                severity: .fatal,
                code: .emptyResult,
                stage: .resultValidation,
                message: "本地执行器没有产出任何指标结果。"
            ))
            return issues
        }

        for result in results {
            if result.rawValue == nil, result.textValue == nil {
                issues.append(ValidationIssue(
                    severity: .fatal,
                    code: .emptyResult,
                    stage: .resultValidation,
                    message: "指标 \(result.label) 没有可验证数值。",
                    path: "results.\(result.id)"
                ))
            }
            if !result.warnings.isEmpty {
                issues.append(contentsOf: result.warnings.map { warning in
                    ValidationIssue(
                        severity: .warning,
                        code: .insufficientData,
                        stage: .resultValidation,
                        message: "\(result.label)：\(warning)",
                        path: "results.\(result.id)"
                    )
                })
            }
        }

        let duplicateWarnings = manifests.filter { $0.duplicateSummary.exactDuplicateRowCount > 0 }
        for manifest in duplicateWarnings {
            issues.append(ValidationIssue(
                severity: .warning,
                code: .duplicateRecordRisk,
                stage: .resultValidation,
                message: "\(manifest.displayName) 存在 \(manifest.duplicateSummary.exactDuplicateRowCount) 行完全重复记录，COUNT/SUM 可能需要业务去重口径。"
            ))
        }
        return issues
    }
}
