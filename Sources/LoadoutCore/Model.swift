import Foundation

/// What kind of thing an inventory entry is.
public enum ItemKind: String, Codable, Sendable, CaseIterable {
    case skill
    case command
    case agent
    case mcp
    case plugin

    public var label: String {
        switch self {
        case .skill: return "技能"
        case .command: return "命令"
        case .agent: return "子代理"
        case .mcp: return "MCP"
        case .plugin: return "插件"
        }
    }

    /// How the thing is named to an assistant being told what it is looking at — lowercase, and
    /// spelled out where the short label would mean nothing out of context.
    public var briefingNoun: String {
        switch self {
        case .skill: return "skill"
        case .command: return "slash command"
        case .agent: return "subagent"
        case .mcp: return "MCP server"
        case .plugin: return "plugin"
        }
    }
}

/// Where the entry comes from. This is a property of the file on disk, never a view state.
public enum Origin: Equatable, Hashable, Codable, Sendable {
    /// `~/.claude/…` — active in every project.
    case personal
    /// `<repo>/.claude/…` — active only inside that repo.
    case project(String)
    /// Shipped by an installed plugin. Read-only for us.
    case plugin(String)

    public var label: String {
        switch self {
        case .personal: return "personal"
        case .project(let name): return name
        case .plugin(let name): return name
        }
    }

    public var isEditable: Bool {
        switch self {
        case .personal, .project: return true
        case .plugin: return false
        }
    }
}

/// One row in the inventory.
public struct Item: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var kind: ItemKind
    public var origin: Origin
    public var description: String
    /// Top-level frontmatter keys and their readable values. Kept as data so the inventory can
    /// filter and sort generically without knowing which assistant invented a field.
    public var frontmatter: [String: String]
    /// The file that defines it (`SKILL.md`, the command's `.md`, …). Nil for MCP servers,
    /// which live inside a JSON blob rather than in a file of their own.
    public var path: URL?
    /// The directory that holds it, when it owns one. This is what we move to disable.
    public var directory: URL?
    public var modified: Date?
    public var enabled: Bool
    /// Set when the frontmatter could not be read, so the UI can say so instead of lying.
    public var warning: String?
    public var usage: Usage
    /// Ids of the assistants that load this item: the ones a personal skill or command is linked
    /// into, or the single owner of an MCP server — whose file the switch has to write. Empty for
    /// everything else.
    public var assistants: Set<String>
    /// What it costs to keep installed, and whether it breaks a documented limit. Only
    /// meaningful for items that own a markdown document.
    public var budget: Budget
    /// `"vercel@claude-plugins-official"` for anything a plugin ships, so a row can act on the
    /// plugin it came from without going looking for it. Nil for everything else.
    public var pluginID: String?
    /// The project directory an MCP server is declared under, exactly as `~/.claude.json` keys it.
    ///
    /// The row shows the folder's name, and two checkouts can share one — `~/work/app` and
    /// `~/personal/app` — so acting on the name alone would switch off a server belonging to the
    /// other one. Nil for a global server.
    public var projectDirectory: String?
    /// True for an MCP server the repository itself ships in its `.mcp.json`, the file a team
    /// commits so everyone gets the same servers.
    ///
    /// Worth a flag of its own because it changes who owns the thing: a server in `~/.claude.json`
    /// is yours to remove, and one in here is the team's. Switching it off is recorded in your own
    /// config as a server you declined, so nobody else's checkout changes.
    public var declaredByRepository = false

    public init(
        id: String,
        name: String,
        kind: ItemKind,
        origin: Origin,
        description: String = "",
        frontmatter: [String: String] = [:],
        path: URL? = nil,
        directory: URL? = nil,
        modified: Date? = nil,
        enabled: Bool = true,
        warning: String? = nil,
        usage: Usage = .none,
        assistants: Set<String> = [],
        budget: Budget = Budget(),
        pluginID: String? = nil,
        projectDirectory: String? = nil,
        declaredByRepository: Bool = false
    ) {
        self.assistants = assistants
        self.budget = budget
        self.pluginID = pluginID
        self.projectDirectory = projectDirectory
        self.declaredByRepository = declaredByRepository
        self.id = id
        self.name = name
        self.kind = kind
        self.origin = origin
        self.description = description
        self.frontmatter = frontmatter
        self.path = path
        self.directory = directory
        self.modified = modified
        self.enabled = enabled
        self.warning = warning
        self.usage = usage
    }

    /// Plugin-owned files are never ours to rewrite.
    public var isEditable: Bool { origin.isEditable && kind != .mcp && kind != .plugin }
}

/// How much an item has actually been used, mined from session transcripts.
public struct Usage: Equatable, Sendable, Codable {
    public var count: Int
    public var lastUsed: Date?
    public var projectCount: Int

    public static let none = Usage(count: 0, lastUsed: nil, projectCount: 0)

    public init(count: Int, lastUsed: Date?, projectCount: Int) {
        self.count = count
        self.lastUsed = lastUsed
        self.projectCount = projectCount
    }

    public var neverUsed: Bool { count == 0 }
}

/// One project an item was actually used in, and how often. The named half of `Usage`.
public struct ProjectUsage: Identifiable, Equatable, Hashable, Sendable {
    public var project: String
    public var count: Int

    public var id: String { project }

    public init(project: String, count: Int) {
        self.project = project
        self.count = count
    }
}

/// A repository the owner works in, found inside one of the folders they pointed Loadout at.
public struct Project: Identifiable, Equatable, Hashable, Sendable {
    public var id: String { path.path }
    public var name: String
    public var relativePath: String
    public var path: URL

    public init(name: String, relativePath: String, path: URL) {
        self.name = name
        self.relativePath = relativePath
        self.path = path
    }
}

/// An installed plugin, with the toggle state we can actually change.
public struct PluginInfo: Identifiable, Equatable, Sendable {
    public var assistant: String
    public var nativeKey: String
    /// A provider or policy may expose an installation without a local enable switch.
    public var toggleUnavailableReason: String?
    public var assistantLabel: String { assistant == "codex" ? "Codex" : "Claude Code" }
    /// `"vercel@claude-plugins-official"` — the key `enabledPlugins` uses.
    public var id: String
    public var name: String
    public var marketplace: String
    public var version: String
    public var installPath: URL
    /// What is actually in effect, which in a project scope can be the repository's decision rather
    /// than yours.
    public var enabled: Bool
    /// What the repository being looked at says about this plugin, and nil when it says nothing.
    ///
    /// Claude Code reads a repository's `.claude/settings.json` after your own settings, so this
    /// overrules you. Worth carrying separately because the switch in the app writes to *your*
    /// settings: against a repository that decided, flipping it would change a file and nothing
    /// else, and the app has to say so instead of appearing to work.
    public var repositoryChoice: Bool?

    public init(
        id: String, name: String, marketplace: String, version: String, installPath: URL,
        enabled: Bool, repositoryChoice: Bool? = nil, assistant: String = "claude",
        nativeKey: String? = nil, toggleUnavailableReason: String? = nil
    ) {
        self.assistant = assistant
        self.nativeKey = nativeKey ?? id
        self.toggleUnavailableReason = toggleUnavailableReason
        self.id = id
        self.name = name
        self.marketplace = marketplace
        self.version = version
        self.installPath = installPath
        self.enabled = enabled
        self.repositoryChoice = repositoryChoice
    }
}

/// Errors surfaced to the user verbatim, so a failure always says what happened and what to do.
public enum LoadoutError: LocalizedError, Equatable {
    case notEditable(String)
    case alreadyExists(URL)
    case invalidName(String)
    case missingField(String)
    case backupFailed(String)
    case claudeNotFound
    case notFound(String)
    case io(String)
    case invalidAssistantCLI(String)

    public var errorDescription: String? {
        switch self {
        case .notEditable(let what):
            return "\(what) 来自插件，是只读的。请改用插件开关。"
        case .alreadyExists(let url):
            return "\(url.path) 已经有东西了。没有做任何更改。"
        case .invalidName(let name):
            return "名称“\(name)”无效。只能用小写字母、数字和连字符，比如 imark-review。"
        case .missingField(let field):
            return "frontmatter 缺少 \(field) 字段。"
        case .backupFailed(let reason):
            return "无法创建备份，所以什么都没写入。\(reason)"
        case .claudeNotFound:
            return "找不到可运行的助手 CLI。请安装 Claude Code、Codex、Cursor 或 opencode。"
        case .notFound(let what):
            return "找不到 \(what)。"
        case .io(let reason):
            return reason
        case .invalidAssistantCLI(let reason):
            return reason
        }
    }
}
