import Foundation

struct AnalysisPlannerClient {
    func generatePlan(
        userQuery: String,
        manifests: [TableManifest],
        settings: AISettings
    ) async throws -> AnalysisPlan {
        let localPlan = Self.deterministicPlan(userQuery: userQuery, manifests: manifests)
        guard !settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return localPlan
        }

        let prompt = Self.plannerPrompt(userQuery: userQuery, manifests: manifests)
        do {
            let output = try await AIJobQueue(maxAttempts: 2).runTextJob(
                prompt: prompt,
                settings: settings,
                jobType: "Analysis Harness 计划生成",
                validation: { output in
                    do {
                        _ = try Self.decodePlan(from: output)
                        return []
                    } catch {
                        return ["计划 JSON 无法解析：\(error.localizedDescription)"]
                    }
                },
                correctionPrompt: { originalPrompt, output, warnings in
                    """
                    \(originalPrompt)

                    上一次输出不是可解析的 AnalysisPlan JSON。错误：
                    \(warnings.joined(separator: "\n"))

                    上一次输出：
                    \(output)

                    请只返回 JSON 对象，不要 Markdown，不要解释。
                    """
                }
            ).output
            return try Self.decodePlan(from: output)
        } catch {
            return localPlan
        }
    }

    static func deterministicPlan(userQuery: String, manifests: [TableManifest]) -> AnalysisPlan {
        guard let table = manifests.first else {
            return AnalysisPlan(userQuestion: userQuery, tablesUsed: [], metrics: [], limitations: ["当前任务没有选表。"])
        }
        if let metricNameColumn = table.metricNameColumn,
           let metricValueColumn = table.metricValueColumn {
            let metricLabels = requestedMetricLabels(userQuery: userQuery, table: table, metricNameColumn: metricNameColumn.name)
            let labels = metricLabels.isEmpty ? Array(metricNameColumn.sampleValues.prefix(8)) : metricLabels
            let periodField = table.periodColumn?.name
            let metrics = labels.enumerated().map { index, label in
                MetricDefinition(
                    label: label,
                    operation: .sum,
                    tableID: table.id,
                    field: metricValueColumn.name,
                    groupBy: periodField.map { [$0] } ?? [],
                    filters: [HarnessFilterDefinition(field: metricNameColumn.name, op: .equals, value: label)],
                    unit: unitGuess(for: label),
                    methodology: "按 \(metricNameColumn.name)=\(label) 过滤后，对 \(metricValueColumn.name) 执行 SUM。"
                )
            }
            return AnalysisPlan(
                userQuestion: userQuery,
                tablesUsed: [table.id],
                metrics: metrics,
                assumptions: [HarnessAnalysisAssumption(label: "默认聚合口径", detail: "对可加指标采用全周期 SUM；派生指标须基于 SUM 分子/分母重算。", affectsResult: true)],
                limitations: table.warnings,
                createdBy: "local_manifest_planner"
            )
        }

        let selectedColumns = requestedColumns(userQuery: userQuery, table: table)
        let numericColumns = selectedColumns.isEmpty
            ? table.columns.filter { $0.aggregationRisk == .safeSum || $0.aggregationRisk == .safeAverage }
            : selectedColumns.filter { $0.inferredType == .number || $0.inferredType == .integer }
        let metrics = numericColumns.prefix(12).map { column in
            MetricDefinition(
                label: column.name,
                operation: column.aggregationRisk == .safeAverage ? .avg : .sum,
                tableID: table.id,
                field: column.name,
                unit: unitGuess(for: column.name),
                methodology: column.aggregationRisk == .safeAverage ? "对 \(column.name) 执行 AVG。" : "对 \(column.name) 执行 SUM。"
            )
        }
        if metrics.isEmpty {
            return AnalysisPlan(
                userQuestion: userQuery,
                tablesUsed: [table.id],
                metrics: [
                    MetricDefinition(
                        label: "行数",
                        operation: .countRows,
                        tableID: table.id,
                        methodology: "统计当前选表可读取行数。"
                    )
                ],
                limitations: table.warnings + ["未识别到可加数值指标，先输出行数。"],
                createdBy: "local_manifest_planner"
            )
        }
        return AnalysisPlan(
            userQuestion: userQuery,
            tablesUsed: [table.id],
            metrics: metrics,
            assumptions: [HarnessAnalysisAssumption(label: "默认聚合口径", detail: "对可加指标采用全周期 SUM；比例、人均、笔均类指标不直接 SUM。", affectsResult: true)],
            limitations: table.warnings,
            createdBy: "local_manifest_planner"
        )
    }

    private static func requestedColumns(userQuery: String, table: TableManifest) -> [ColumnManifest] {
        let query = userQuery.normalizedKey
        return table.columns.filter { column in
            let key = column.name.normalizedKey
            guard key.count >= 2 else { return false }
            return query.contains(key) || query.contains(column.name)
        }
    }

    private static func requestedMetricLabels(
        userQuery: String,
        table: TableManifest,
        metricNameColumn: String
    ) -> [String] {
        let query = userQuery.normalizedKey
        guard let column = table.columns.first(where: { $0.name == metricNameColumn }) else { return [] }
        return column.sampleValues.filter { value in
            let key = value.normalizedKey
            return key.count >= 2 && query.contains(key)
        }
    }

    private static func unitGuess(for label: String) -> String {
        let key = label.normalizedKey
        if key.contains("金额") || key.contains("amount") || key.contains("mxn") { return "MXN" }
        if key.contains("人数") || key.contains("user") { return "人" }
        if key.contains("笔数") || key.contains("count") { return "笔" }
        if key.contains("%") || key.contains("占比") || key.contains("率") { return "%" }
        return ""
    }

    private static func plannerPrompt(userQuery: String, manifests: [TableManifest]) -> String {
        let manifestJSON = (try? String(data: JSONEncoder.harnessEncoder.encode(manifests), encoding: .utf8)) ?? "[]"
        return """
        你是 Analysis Harness 的计划生成器。只输出 AnalysisPlan JSON，不要 Markdown。
        任务：根据用户问题和 TableManifest 生成可由本地执行器执行的计划。
        规则：
        - metrics.operation 只能使用 count_rows/count_distinct/sum/avg/min/max/calculate_ratio/calculate_growth_rate/calculate_difference。
        - 不要对 rate/占比/率 字段使用 sum。
        - 不能凭空引用不存在的 tableID 或字段。
        - 派生指标必须通过 numeratorMetricID/denominatorMetricID 或 baseMetricID/comparisonMetricID 表达。
        - 知识库和外部参照不能参与指标计算。

        用户问题：
        \(userQuery)

        TableManifest JSON：
        \(manifestJSON)

        只返回 JSON 对象。
        """
    }

    private static func decodePlan(from output: String) throws -> AnalysisPlan {
        let json = HarnessJSONExtractor.extractJSONObject(from: output)
        return try JSONDecoder.harnessDecoder.decode(AnalysisPlan.self, from: Data(json.utf8))
    }
}

struct PlanValidator {
    static func validate(plan: AnalysisPlan, manifests: [TableManifest]) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        let manifestByID = Dictionary(uniqueKeysWithValues: manifests.map { ($0.id, $0) })

        if plan.metrics.isEmpty, plan.createdBy != "normalized_fact_table" {
            issues.append(ValidationIssue(
                severity: .fatal,
                code: .insufficientData,
                stage: .planValidation,
                message: "分析计划没有任何可执行指标。"
            ))
        }

        for tableID in plan.tablesUsed where manifestByID[tableID] == nil {
            issues.append(ValidationIssue(
                severity: .fatal,
                code: .missingTable,
                stage: .planValidation,
                message: "计划引用了不存在的表：\(tableID)。",
                path: "tablesUsed"
            ))
        }

        for relationship in plan.relationships where !relationship.safeToJoin {
            issues.append(ValidationIssue(
                severity: .fatal,
                code: .unsafeJoin,
                stage: .planValidation,
                message: "计划包含未确认安全性的 join：\(relationship.leftTableID) -> \(relationship.rightTableID)。\(relationship.reason)",
                path: "relationships"
            ))
        }

        for metric in plan.metrics {
            guard let table = manifestByID[metric.tableID] else {
                issues.append(ValidationIssue(
                    severity: .fatal,
                    code: .missingTable,
                    stage: .planValidation,
                    message: "指标 \(metric.label) 引用了不存在的表 \(metric.tableID)。",
                    path: "metrics.\(metric.id).tableID"
                ))
                continue
            }
            if let field = metric.field {
                guard let column = table.columns.first(where: { $0.name == field }) else {
                    issues.append(ValidationIssue(
                        severity: .fatal,
                        code: .missingField,
                        stage: .planValidation,
                        message: "指标 \(metric.label) 引用了不存在的字段 \(field)。",
                        path: "metrics.\(metric.id).field"
                    ))
                    continue
                }
                if metric.operation == .sum, column.aggregationRisk == .rateLike {
                    issues.append(ValidationIssue(
                        severity: .fatal,
                        code: .rateAggregationError,
                        stage: .planValidation,
                        message: "指标 \(metric.label) 试图对比例/占比字段 \(field) 求和。",
                        path: "metrics.\(metric.id).operation",
                        fixHint: "比例字段应使用加权重算或 AVG，并声明限制。"
                    ))
                }
                if metric.operation == .countDistinct, column.aggregationRisk != .idLike {
                    issues.append(ValidationIssue(
                        severity: .warning,
                        code: .distinctCountRisk,
                        stage: .planValidation,
                        message: "指标 \(metric.label) 对非 ID 字段 \(field) 去重计数，可能不是业务实体口径。",
                        path: "metrics.\(metric.id).field"
                    ))
                }
            }
            for groupField in metric.groupBy where !table.columns.contains(where: { $0.name == groupField }) {
                issues.append(ValidationIssue(
                    severity: .fatal,
                    code: .missingField,
                    stage: .planValidation,
                    message: "指标 \(metric.label) 的分组字段不存在：\(groupField)。",
                    path: "metrics.\(metric.id).groupBy"
                ))
            }
            for filter in metric.filters where !table.columns.contains(where: { $0.name == filter.field }) {
                issues.append(ValidationIssue(
                    severity: .fatal,
                    code: .missingField,
                    stage: .planValidation,
                    message: "指标 \(metric.label) 的过滤字段不存在：\(filter.field)。",
                    path: "metrics.\(metric.id).filters"
                ))
            }
        }

        if plan.assumptions.isEmpty {
            issues.append(ValidationIssue(
                severity: .warning,
                code: .missingAssumption,
                stage: .planValidation,
                message: "计划没有声明聚合口径假设。"
            ))
        }
        return issues
    }
}

struct PlanRepairLoop {
    static func repair(
        plan: AnalysisPlan,
        issues: [ValidationIssue],
        manifests: [TableManifest],
        userQuery: String
    ) -> (plan: AnalysisPlan, attempts: Int, issues: [ValidationIssue]) {
        guard issues.contains(where: { $0.severity.blocksOutput }) else {
            return (plan, 0, issues)
        }
        let validTableIDs = Set(manifests.map(\.id))
        let manifestByID = Dictionary(uniqueKeysWithValues: manifests.map { ($0.id, $0) })
        var repaired = plan
        repaired.tablesUsed = repaired.tablesUsed.filter { validTableIDs.contains($0) }
        repaired.relationships.removeAll { !$0.safeToJoin }
        repaired.metrics = repaired.metrics.compactMap { metric in
            guard let table = manifestByID[metric.tableID] else { return nil }
            var metric = metric
            if let field = metric.field {
                guard let column = table.columns.first(where: { $0.name == field }) else { return nil }
                if metric.operation == .sum, column.aggregationRisk == .rateLike {
                    metric.operation = .avg
                    metric.methodology = "字段 \(field) 是比例/占比字段，已从 SUM 修复为 AVG，并保留口径警告。"
                }
            }
            metric.groupBy = metric.groupBy.filter { field in table.columns.contains(where: { $0.name == field }) }
            metric.filters = metric.filters.filter { filter in table.columns.contains(where: { $0.name == filter.field }) }
            return metric
        }
        if repaired.tablesUsed.isEmpty, let first = manifests.first?.id {
            repaired.tablesUsed = [first]
        }
        if repaired.metrics.isEmpty {
            repaired = AnalysisPlannerClient.deterministicPlan(userQuery: userQuery, manifests: manifests)
            repaired.limitations.append("原计划无法修复，已回退为本地确定性计划。")
        } else {
            repaired.limitations.append("计划经过本地修复：移除了不存在字段/不安全 join，并修正比例聚合。")
        }
        let repairedIssues = PlanValidator.validate(plan: repaired, manifests: manifests)
        return (repaired, 1, repairedIssues)
    }
}
