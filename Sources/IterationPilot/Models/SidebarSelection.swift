import Foundation

enum SidebarSelection: String, CaseIterable, Identifiable, Codable {
    case dashboard
    case businessSpaces
    case dataPacks
    case quality
    case timeline
    case sessions
    case analysis
    case opportunities
    case memo
    case references
    case corrections
    case knowledge
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "流程总览"
        case .businessSpaces: return "业务空间"
        case .dataPacks: return "数据资料"
        case .quality: return "质检详情"
        case .timeline: return "事件时间轴"
        case .sessions: return "分析会话"
        case .analysis: return "分析证据"
        case .opportunities: return "机会评分"
        case .memo: return "报告草稿"
        case .references: return "参照数据源"
        case .corrections: return "记忆中心"
        case .knowledge: return "知识库"
        case .settings: return "AI 设置"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "rectangle.grid.2x2"
        case .businessSpaces: return "globe.asia.australia"
        case .dataPacks: return "tray.and.arrow.down"
        case .quality: return "checkmark.seal"
        case .timeline: return "calendar.badge.clock"
        case .sessions: return "bubble.left.and.text.bubble.right"
        case .analysis: return "chart.line.uptrend.xyaxis"
        case .opportunities: return "scope"
        case .memo: return "doc.text"
        case .references: return "newspaper"
        case .corrections: return "bubble.left.and.bubble.right"
        case .knowledge: return "books.vertical"
        case .settings: return "gearshape"
        }
    }

    static func from(id: String) -> SidebarSelection {
        let selection = SidebarSelection(rawValue: id) ?? .sessions
        return (selection == .dashboard || selection == .memo || selection == .dataPacks) ? .sessions : selection
    }
}
