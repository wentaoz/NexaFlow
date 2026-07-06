import Foundation

enum SampleDataFactory {
    static func makeWorkspace() -> ProductWorkspace {
        let pack = makeSamplePack()
        return ProductWorkspace(dataPacks: [pack], knowledgeEntries: makeKnowledgeEntries(), aiSettings: .default)
    }

    static func makeSamplePack() -> DataPack {
        let updates = [
            ProductUpdate(
                id: UUID(),
                date: date("2026-05-10"),
                module: "新用户 onboarding",
                changeType: "流程优化",
                targetUser: "新用户 / Android",
                expectedMetric: "activation_rate",
                owner: "产品负责人",
                releaseNote: "注册后首屏从 5 个选择项缩短为 3 个步骤，并调整权限请求时机。",
                riskNote: "可能影响高意向用户对高级功能的理解。"
            ),
            ProductUpdate(
                id: UUID(),
                date: date("2026-05-14"),
                module: "会员购买页",
                changeType: "文案实验",
                targetUser: "全量 / Web",
                expectedMetric: "pay_conversion",
                owner: "增长产品",
                releaseNote: "会员权益说明改为收益优先展示，并弱化折扣倒计时。",
                riskNote: "短期点击可能下降。"
            )
        ]

        let events = [
            ProductEvent(id: UUID(), date: date("2026-05-12"), eventType: "运营活动", title: "会员周折扣", scope: "全量", note: "5 月 12 日至 5 月 16 日部分渠道展示优惠券。"),
            ProductEvent(id: UUID(), date: date("2026-05-13"), eventType: "技术异常", title: "Android 图片 CDN 延迟", scope: "Android", note: "首屏资源加载变慢约 400ms，下午恢复。"),
            ProductEvent(id: UUID(), date: date("2026-05-16"), eventType: "竞品动态", title: "竞品发布免费试用版本", scope: "市场", note: "竞品将免费试用从 3 天延长到 7 天。")
        ]

        let metrics = makeMetrics()
        let feedback = [
            FeedbackItem(id: UUID(), date: date("2026-05-11"), source: "客服", module: "onboarding", segment: "新用户 / Android", sentiment: "负向", text: "用户反馈不知道下一步为什么要开启权限。"),
            FeedbackItem(id: UUID(), date: date("2026-05-13"), source: "应用商店", module: "onboarding", segment: "新用户 / Android", sentiment: "负向", text: "注册后页面加载慢，点击继续没有反应。"),
            FeedbackItem(id: UUID(), date: date("2026-05-15"), source: "访谈", module: "会员购买页", segment: "高意向用户 / Web", sentiment: "正向", text: "新权益说明更容易理解，但希望看到对比表。")
        ]

        var pack = DataPack(
            id: UUID(),
            name: "示例数据包 2026-W20",
            period: "2026-W20",
            importedAt: Date(),
            sourcePath: nil,
            manifest: DataManifest(
                period: "2026-W20",
                exportedAt: date("2026-05-18"),
                exportedBy: "示例数据",
                sources: [
                    ManifestSource(name: "core_metrics_daily.csv", platform: "示例数据平台", dateRange: "2026-05-01 to 2026-05-17", exportMethod: "manual_csv"),
                    ManifestSource(name: "product_updates.csv", platform: "产品更新表", dateRange: "2026-05-01 to 2026-05-17", exportMethod: "manual_csv")
                ],
                knownIssues: ["5 月 13 日 Android CDN 延迟可能影响 onboarding 指标。"]
            ),
            productUpdates: updates,
            metrics: metrics,
            events: events,
            feedback: feedback,
            qualityReport: QualityReport(generatedAt: Date(), verdict: .usable, issues: [], stats: QualityStats(updateCount: 0, metricCount: 0, eventCount: 0, feedbackCount: 0, metricDateCount: 0)),
            analysisReport: AnalysisReport(generatedAt: Date(), summary: "", metricInsights: [], attributionFindings: [], opportunities: []),
            decisionMemo: DecisionMemo(generatedAt: Date(), markdown: "", aiSupplement: "")
        )
        pack.qualityReport = AnalysisEngine.buildQualityReport(for: pack)
        pack.analysisReport = AnalysisEngine.analyze(pack: pack)
        pack.decisionMemo = DecisionMemo(generatedAt: Date(), markdown: AnalysisEngine.generateMemo(for: pack), aiSupplement: "")
        return pack
    }

    private static func makeMetrics() -> [MetricPoint] {
        let days = (1...17).map { String(format: "2026-05-%02d", $0) }
        var points: [MetricPoint] = []

        for (index, day) in days.enumerated() {
            let isAfterUpdate = index >= 10
            let androidActivation = isAfterUpdate ? 0.35 + Double(index % 2) * 0.01 : 0.42 + Double(index % 3) * 0.005
            let iosActivation = isAfterUpdate ? 0.43 + Double(index % 2) * 0.003 : 0.42 + Double(index % 3) * 0.004
            let payConversion = index >= 13 ? 0.071 + Double(index % 2) * 0.002 : 0.062 + Double(index % 3) * 0.001
            let dau = index >= 15 ? 12400 - Double(index * 90) : 11800 + Double(index * 120)

            points.append(MetricPoint(id: UUID(), date: date(day), metric: "activation_rate", value: androidActivation, segment: "新用户", platform: "Android", channel: "全渠道"))
            points.append(MetricPoint(id: UUID(), date: date(day), metric: "activation_rate", value: iosActivation, segment: "新用户", platform: "iOS", channel: "全渠道"))
            points.append(MetricPoint(id: UUID(), date: date(day), metric: "pay_conversion", value: payConversion, segment: "全量", platform: "Web", channel: "全渠道"))
            points.append(MetricPoint(id: UUID(), date: date(day), metric: "DAU", value: dau, segment: "全量", platform: "全平台", channel: "全渠道"))
        }

        return points
    }

    private static func makeKnowledgeEntries() -> [KnowledgeEntry] {
        [
            KnowledgeEntry(
                id: UUID(),
                createdAt: date("2026-05-01"),
                scenario: "新用户 onboarding",
                problem: "新用户激活率低",
                action: "减少首屏选择项，并将权限请求后置。",
                result: "低意向用户完成率提升，但 Android 加载性能会明显影响结果。",
                evidenceLevel: .b,
                relatedPackName: "历史复盘样例"
            )
        ]
    }

    private static func date(_ rawValue: String) -> Date {
        DateParsing.parse(rawValue) ?? Date()
    }
}
