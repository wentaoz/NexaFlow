import AppKit
import Foundation

@MainActor
extension ProductWorkflowStore {
    func notifyPersistentAIJobCompletionIfNeeded(_ job: PersistentAIJob) {
        let settings = workspace.notificationSettings
        guard settings.isEnabled else { return }

        let title: String
        let body: String
        switch job.kind {
        case .analysisSession:
            guard settings.notifyAIReplyCompleted else { return }
            title = "AI 回复已完成"
            body = "\(job.targetName.nilIfBlank ?? "当前分析会话") 已生成最新回答。"
        case .memo:
            guard settings.notifyReportGenerated else { return }
            title = "完整汇报已生成"
            body = "\(job.targetName.nilIfBlank ?? "当前分析会话") 的完整汇报已完成，可返回 App 查看或导出。"
        default:
            return
        }

        AppNotificationService.shared.deliver(
            identifier: "iteration-pilot-\(job.id.uuidString)",
            title: title,
            body: body,
            shouldNotifyWhenAppActive: settings.notifyWhenAppActive
        )
    }
}
