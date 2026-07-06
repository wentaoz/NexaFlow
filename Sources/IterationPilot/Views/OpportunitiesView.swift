import SwiftUI

struct OpportunitiesView: View {
    @EnvironmentObject private var store: ProductWorkflowStore

    var body: some View {
        ScrollView {
            if let pack = store.selectedPack {
                let opportunities = store.currentAnalysisTask(in: pack)?.analysisReport.opportunities ?? pack.analysisReport.opportunities
                LazyVStack(alignment: .leading, spacing: 16) {
                    Text("机会评分")
                        .font(.largeTitle)
                        .fontWeight(.semibold)

                    SectionCard(title: "评分模型", systemImage: "function") {
                        Text("Priority Score = Impact × Confidence × Urgency × Strategic Fit / (Effort + Risk)。AI 只生成建议，最终优先级需要产品负责人确认。")
                            .foregroundStyle(.secondary)
                    }

                    SectionCard(title: "候选机会", systemImage: "scope") {
                        if opportunities.isEmpty {
                            emptyOpportunityState
                        } else {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(opportunities) { opportunity in
                                    OpportunityRow(opportunity: opportunity)
                                    Divider()
                                }
                            }
                        }
                    }
                }
                .padding(18)
            } else {
                EmptyStateView(title: "没有机会评分", detail: "导入数据并完成分析后会生成候选机会。", systemImage: "scope")
            }
        }
    }

    @ViewBuilder
    private var emptyOpportunityState: some View {
        let hasAIAnalysis = store.selectedAnalysisSession?.messages.contains { $0.role == .assistant && $0.kind == .aiAnalysis } == true
        VStack(alignment: .leading, spacing: 10) {
            if hasAIAnalysis {
                Text("AI 已完成分析，但尚未生成结构化机会评分，或上一轮没有形成可排序机会。")
                    .foregroundStyle(.secondary)
                Button {
                    store.regenerateOpportunitiesForSelectedSession()
                } label: {
                    Label("重新生成机会评分", systemImage: "scope")
                }
                .disabled(!store.hasConfiguredAI || store.isRunningAI)
            } else {
                Text("请先在分析会话中选择报表、填写需求并发送给 AI。AI 分析完成后会自动生成机会评分。")
                    .foregroundStyle(.secondary)
                Button {
                    store.requestAnalysisSessionNavigation()
                } label: {
                    Label("去分析会话", systemImage: "bubble.left.and.text.bubble.right")
                }
            }
        }
    }
}

private struct OpportunityRow: View {
    var opportunity: ProductOpportunity

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(opportunity.title)
                    .font(.headline)
                Spacer()
                Badge(text: "优先级 \(opportunity.priorityLabel)", systemImage: nil, tint: opportunity.priorityLabel == "高" ? AppTheme.danger : opportunity.priorityLabel == "中" ? AppTheme.warning : .secondary)
                Text(opportunity.score.compactText)
                    .font(.headline)
                    .monospacedDigit()
            }
            Text(opportunity.problem)
                .font(.callout)
            Text("影响用户：\(opportunity.affectedUsers)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !opportunity.evidenceSummary.isEmpty {
                Text("证据：\(opportunity.evidenceSummary)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Badge(text: opportunity.isAIGenerated ? "AI 生成" : "本地/历史", systemImage: nil, tint: opportunity.isAIGenerated ? AppTheme.accent : .secondary)
                Badge(text: opportunity.isUserConfirmed ? "已确认" : "待确认", systemImage: nil, tint: opportunity.isUserConfirmed ? AppTheme.success : AppTheme.warning)
                if !opportunity.sourceSessionTitle.isEmpty {
                    Text("来源：\(opportunity.sourceSessionTitle)")
                        .lineLimit(1)
                }
                Text(DateFormatting.shortDateTime.string(from: opportunity.generatedAt))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                ScoreChip(title: "影响", value: opportunity.expectedImpact)
                ScoreChip(title: "置信", value: opportunity.confidence)
                ScoreChip(title: "紧急", value: opportunity.urgency)
                ScoreChip(title: "成本", value: opportunity.effort)
                ScoreChip(title: "风险", value: opportunity.risk)
                ScoreChip(title: "战略", value: opportunity.strategicFit)
            }
        }
        .padding(.vertical, 8)
    }
}

private struct ScoreChip: View {
    var title: String
    var value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(value)")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            ProgressView(value: Double(value), total: 10)
                .progressViewStyle(.linear)
        }
        .padding(8)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
    }
}
