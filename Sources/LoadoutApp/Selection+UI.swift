import SwiftUI
import LoadoutCore

/// What the UI layer knows about each sidebar kind beyond its core identity: a tooltip
/// sentence and what the search placeholder calls it.
extension Selection {
    /// What clicking this tab switches the window to, said as a sentence for the hover tooltip.
    var rowHint: String {
        switch self {
        case .skills: return "Claude 和其他助手在需要时自动加载的技能"
        case .commands: return "Claude 在每个项目里都能用的斜杠命令"
        case .agents: return "Claude 可以把任务委派给它们的子代理"
        case .mcp: return "为 Claude 配置的 MCP 服务器"
        case .plugins: return "通过 Claude Code 安装的插件，以及它们的启用状态"
        }
    }

    /// What the search field's placeholder calls a row of this kind — "Search 56 skills",
    /// singular when there is only one.
    func searchNoun(plural: Bool) -> String {
        switch self {
        case .skills: return "技能"
        case .commands: return "命令"
        case .agents: return "子代理"
        case .mcp: return "MCP 服务器"
        case .plugins: return "插件"
        }
    }

    /// A count with its measure word, "56 个技能" / "3 条命令".
    func counted(_ count: Int) -> String {
        "\(count) \(self == .commands ? "条" : "个")\(searchNoun(plural: count != 1))"
    }
}
