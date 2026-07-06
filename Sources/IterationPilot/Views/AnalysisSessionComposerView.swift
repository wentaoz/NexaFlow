import SwiftUI

struct InlineThinkingStatusView: View {
    var job: LiveAIJobSnapshot
    var cancelAction: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Button(role: .destructive) {
                cancelAction()
            } label: {
                Label("停止", systemImage: "stop.circle")
            }
            .buttonStyle(AppHoverButtonStyle(variant: .danger))
            .controlSize(.small)
            .help("停止当前 AI 分析，迟到结果不会写入会话")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AppTheme.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(AppTheme.accent.opacity(0.18), lineWidth: 1)
        )
    }

    private var latestDetail: String {
        job.latestDetail
    }

    private var title: String {
        if job.status == .waiting && job.delayedRetryCount > 0 {
            return "自动重试中"
        }
        if latestDetail.contains("准备") || latestDetail.contains("读取") {
            return "正在准备分析资料"
        }
        if latestDetail.localizedCaseInsensitiveContains("Prompt") {
            return "正在组织本轮问题"
        }
        if latestDetail.contains("请求") || latestDetail.contains("等待 AI") {
            return "正在请求 AI"
        }
        if latestDetail.contains("整理") || latestDetail.contains("写入") {
            return "正在整理回答"
        }
        if job.kind == .simpleReportGeneration {
            return job.status == .waiting ? "简洁汇报排队中" : "正在生成简洁汇报"
        }
        if job.kind == .memo {
            return job.status == .waiting ? "完整汇报排队中" : "正在生成完整汇报"
        }
        return job.status == .waiting ? "分析排队中" : "正在分析"
    }

    private var detail: String {
        guard !latestDetail.isEmpty else {
            return job.status == .waiting ? "任务已排队，后台会自动开始。" : "请稍候，当前会话正在处理。"
        }
        return latestDetail
    }
}
