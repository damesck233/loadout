import Foundation

/// Uses Codex's local inventory as the authority for installed versions. Cached packages
/// only supply the children that Codex deliberately omits when their parent is disabled.
struct CodexPlugins {
    let paths: Paths

    func scan(project: Project? = nil) -> Inventory {
        guard FileManager.default.fileExists(atPath: paths.codexHome.path) else { return Inventory() }
        guard paths.codexExecutable != nil else {
            // Test homes and installations without plugins do not require a provider process.
            guard FileManager.default.fileExists(atPath: paths.codexPluginCache.path) else { return Inventory() }
            return Inventory(diagnostics: ["无法读取 Codex 插件。请安装或更新 Codex，然后重新载入。"])
        }
        do {
            let connection = try CodexConnection(paths: paths)
            defer { connection.close() }
            let cwd = project?.path ?? paths.home
            let settings = try connection.call("config/read", ["includeLayers": true, "cwd": cwd.path])
            let installed = try connection.call("plugin/installed", ["cwds": [cwd.path]])
            let skills = try connection.call("skills/list", ["cwds": [cwd.path], "forceReload": true])
            return try inventory(installed: installed, skills: skills, settings: settings, connection: connection)
        } catch {
            return Inventory(diagnostics: [error.localizedDescription])
        }
    }

    /// Also used by fixture tests: native responses are data, not an excuse to read the real home.
    func inventory(installed: [String: Any], skills: [String: Any], settings: [String: Any],
                   connection: CodexConnection? = nil) throws -> Inventory {
        guard let marketplaces = installed["marketplaces"] as? [[String: Any]],
              let entries = skills["data"] as? [[String: Any]],
              let config = settings["config"] as? [String: Any] else {
            throw LoadoutError.io("Codex 返回的插件清单格式不受支持。请更新 Codex 并重新载入。")
        }
        var result = Inventory()
        result.items += Self.servers(in: config, file: paths.codexConfig)
        for error in installed["marketplaceLoadErrors"] as? [[String: Any]] ?? [] {
            result.diagnostics.append("Codex 插件市场：\(error["message"] as? String ?? "无法读取")")
        }
        let nativeSkills = entries.flatMap { $0["skills"] as? [[String: Any]] ?? [] }
        var overrides = (config["skills"] as? [String: Any])?["config"] as? [[String: Any]] ?? []
        let flags = config["plugins"] as? [String: Any] ?? [:]
        let scanner = InventoryScanner(paths: paths)
        for marketplace in marketplaces {
            for summary in marketplace["plugins"] as? [[String: Any]] ?? [] {
                guard summary["installed"] as? Bool == true,
                      let key = summary["id"] as? String,
                      let name = summary["name"] as? String,
                      let market = marketplace["name"] as? String,
                      let parentEnabled = summary["enabled"] as? Bool else { continue }
                let id = "codex:\(key)"
                let owned = nativeSkills.filter { $0["pluginId"] as? String == key }
                let version = summary["localVersion"] as? String
                let source = summary["source"] as? [String: Any] ?? [:]
                var root: URL?
                if let version, Self.component(version), Self.component(market), Self.component(name) {
                    root = paths.codexPluginCache.appendingPathComponent(market)
                        .appendingPathComponent(name).appendingPathComponent(version)
                }
                // Remote packages do not always expose localVersion. The runtime's actual skill
                // path identifies its materialized version without picking a directory by date.
                if root == nil, Self.component(market), Self.component(name) {
                    let prefix = paths.codexPluginCache.appendingPathComponent(market).appendingPathComponent(name)
                        .resolvingSymlinksInPath().path + "/"
                    if let file = owned.compactMap({ $0["path"] as? String }).first {
                        let canonical = URL(fileURLWithPath: file).resolvingSymlinksInPath().path
                        if canonical.hasPrefix(prefix), let version = canonical.dropFirst(prefix.count).split(separator: "/").first {
                            root = URL(fileURLWithPath: prefix).appendingPathComponent(String(version))
                        }
                    }
                }
                var unavailable: String?
                if source["type"] as? String == "remote" {
                    unavailable = "这个插件由你的 Codex 工作区管理。请在 Codex 里更改。"
                }
                if let policy = summary["installPolicy"] as? String, policy == "REQUIRED" {
                    unavailable = "你的 Codex 工作区要求必须装这个插件。"
                }
                let origins = settings["origins"] as? [String: Any] ?? [:]
                for (field, value) in origins where field.contains(key) && field.hasSuffix("enabled") {
                    let origin = (value as? [String: Any])?["name"] as? [String: Any]
                    if let type = origin?["type"] as? String, type != "user", type != "system" {
                        unavailable = "这个插件的状态由另一层 Codex 配置决定。请到那里更改。"
                    }
                }
                let enabled = source["type"] as? String == "remote" ? parentEnabled
                    : ((flags[key] as? [String: Any])?["enabled"] as? Bool ?? parentEnabled)
                let installPath = root ?? paths.codexPluginCache
                var plugin = PluginInfo(id: id, name: name, marketplace: market,
                                        version: version ?? root?.lastPathComponent ?? "",
                                        installPath: installPath, enabled: enabled,
                                        assistant: "codex", nativeKey: key,
                                        toggleUnavailableReason: unavailable)
                var files: [URL] = owned.compactMap { ($0["path"] as? String).map { URL(fileURLWithPath: $0) } }
                if let root {
                    do { files += try Self.manifestSkills(at: root) }
                    catch {
                        result.diagnostics.append("\(name): \(error.localizedDescription)")
                        if files.isEmpty { plugin.toggleUnavailableReason = "无法读取已安装的插件文件。请在 Codex 里修复安装后重新载入。" }
                    }
                } else if source["type"] as? String != "remote" {
                    plugin.toggleUnavailableReason = "Codex 没有识别出已安装的版本。请更新 Codex 并重新载入。"
                    result.diagnostics.append("\(name)：Codex 没有识别出已安装的版本。")
                }
                result.plugins.append(plugin)
                var seen = Set<String>()
                for file in files {
                    let file = file.resolvingSymlinksInPath()
                    guard seen.insert(file.path).inserted,
                          FileManager.default.fileExists(atPath: file.path) else { continue }
                    var item = scanner.skill(at: file.deletingLastPathComponent(), origin: .plugin(name), enabled: true)
                    let native = owned.first { ($0["path"] as? String).map { URL(fileURLWithPath: $0).resolvingSymlinksInPath() == file } ?? false }
                    let qualifiedName = native?["name"] as? String ?? "\(name):\(item.name)"
                    let relative = root.flatMap { Self.relative(file, to: $0) } ?? file.path
                    item.id = "skill:\(id):\(relative)"
                    item.pluginID = id
                    item.assistants = ["codex"]
                    // The qualified name is needed by Codex's native name overrides; the display
                    // name stays readable because the provider and plugin already have labels.
                    var choice = Self.choice(overrides, file: file, name: qualifiedName)
                    var reapplied = false
                    let records = OffRecords(paths: paths)
                    if records.pluginEntries(of: id).contains(relative), let connection {
                        do {
                            if choice == true {
                                try records.forgetPluginEntry(relative, in: id)
                            } else if choice == nil {
                                try Backups(paths: paths).snapshot(paths.codexConfig)
                                let response = try connection.call("skills/config/write", ["path": file.path, "enabled": false])
                                guard response["effectiveEnabled"] as? Bool == false else {
                                    throw LoadoutError.io("Codex 无法恢复 \(item.name) 的停用设置。另一项设置覆盖了它。")
                                }
                                overrides.append(["path": file.path, "enabled": false])
                                choice = false
                                reapplied = true
                            }
                        } catch {
                            result.diagnostics.append("\(name)/\(item.name): \(error.localizedDescription)")
                        }
                    }
                    item.enabled = reapplied ? false : (native?["enabled"] as? Bool ?? choice ?? true)
                    result.items.append(item)
                }
            }
        }
        return result
    }

    static func choice(_ overrides: [[String: Any]], file: URL, name: String) -> Bool? {
        var value: Bool?
        for entry in overrides {
            let matchesPath = (entry["path"] as? String).map {
                let url = URL(fileURLWithPath: $0).resolvingSymlinksInPath()
                return url == file || url == file.deletingLastPathComponent()
            } ?? false
            if matchesPath || entry["name"] as? String == name { value = entry["enabled"] as? Bool }
        }
        return value
    }

    static func component(_ string: String) -> Bool {
        !string.isEmpty && string != "." && string != ".." && !string.contains("/")
    }

    static func relative(_ file: URL, to root: URL) -> String? {
        let prefix = root.resolvingSymlinksInPath().path + "/"
        let path = file.resolvingSymlinksInPath().path
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : nil
    }

    static func manifestSkills(at root: URL) throws -> [URL] {
        let file = root.appendingPathComponent(".codex-plugin/plugin.json")
        // No manifest is not a broken plugin. A connector such as Slack or Google Calendar ships
        // nothing but its MCP server, and Codex installs it without one; the only thing to do is
        // look in the conventional folder and, finding nothing, list the plugin with no skills.
        // A manifest that is there and cannot be read is a different matter, and still throws.
        let object = FileManager.default.fileExists(atPath: file.path)
            ? try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
            : nil
        let locations: [String]
        if let path = object?["skills"] as? String { locations = [path] }
        else if let paths = object?["skills"] as? [String] { locations = paths }
        else if object?["skills"] == nil { locations = ["skills"] }
        else { throw LoadoutError.io("插件清单里的技能位置格式不受支持。") }
        var result: [URL] = []
        var visited = Set<String>()
        func walk(_ folder: URL) {
            let canonical = folder.resolvingSymlinksInPath()
            guard relative(canonical, to: root) != nil || canonical == root.resolvingSymlinksInPath(),
                  visited.insert(canonical.path).inserted else { return }
            let skill = canonical.appendingPathComponent("SKILL.md")
            if FileManager.default.fileExists(atPath: skill.path) { result.append(skill); return }
            for entry in (try? FileManager.default.contentsOfDirectory(at: canonical, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [] {
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: entry.path, isDirectory: &isDirectory), isDirectory.boolValue { walk(entry) }
            }
        }
        for location in locations { walk(root.appendingPathComponent(location)) }
        return result
    }

    func setPlugin(_ plugin: PluginInfo, enabled: Bool) throws {
        if let reason = plugin.toggleUnavailableReason { throw LoadoutError.io(reason) }
        let connection = try CodexConnection(paths: paths)
        defer { connection.close() }
        let settings = try connection.call("config/read", ["includeLayers": true])
        try Backups(paths: paths).snapshot(paths.codexConfig)
        // JSON string escaping is also valid for the quoted TOML key used by this protocol.
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        let quoted = String(data: try encoder.encode(plugin.nativeKey), encoding: .utf8)!
        var params: [String: Any] = ["keyPath": "plugins.\(quoted).enabled", "value": enabled,
                                    "mergeStrategy": "replace", "filePath": paths.codexConfig.path]
        if let layer = (settings["layers"] as? [[String: Any]])?.first(where: {
            ($0["name"] as? [String: Any])?["type"] as? String == "user"
        }), let version = layer["version"] as? String { params["expectedVersion"] = version }
        let response = try connection.call("config/value/write", params)
        if response["status"] as? String != "ok" {
            throw LoadoutError.io("Codex 已保存设置，但被另一项配置覆盖了。请在 Codex 里更改那项覆盖它的设置。")
        }
    }

    /// Codex's own MCP servers, the `[mcp_servers.<name>]` tables of `config.toml` as `config/read`
    /// resolves them. Servers a plugin brings along are not in here — Codex keeps those with the
    /// plugin — so every row is one the person wrote and can switch.
    static func servers(in config: [String: Any], file: URL) -> [Item] {
        let servers = config["mcp_servers"] as? [String: Any] ?? [:]
        return servers.compactMap { name, value -> Item? in
            guard let dict = value as? [String: Any] else { return nil }
            var description = "MCP 服务器"
            if let command = dict["command"] as? String {
                let args = dict["args"] as? [String] ?? []
                description = args.isEmpty ? command : command + " " + args.joined(separator: " ")
            } else if let url = dict["url"] as? String {
                description = url
            }
            return Item(
                id: "mcp:codex:\(name)", name: name, kind: .mcp, origin: .personal,
                description: description, path: file,
                modified: (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                enabled: (dict["enabled"] as? Bool) ?? true, assistants: ["codex"]
            )
        }.sorted { $0.name < $1.name }
    }

    /// The same write the plugin switch does, on `mcp_servers.<name>.enabled`: Codex's own flag,
    /// written by Codex, checked against the version of the file it read.
    func setServer(named name: String, enabled: Bool) throws {
        let connection = try CodexConnection(paths: paths)
        defer { connection.close() }
        let settings = try connection.call("config/read", ["includeLayers": true])
        guard let config = settings["config"] as? [String: Any],
              (config["mcp_servers"] as? [String: Any])?[name] != nil
        else { throw LoadoutError.notFound(name) }
        try Backups(paths: paths).snapshot(paths.codexConfig)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        let quoted = String(data: try encoder.encode(name), encoding: .utf8)!
        var params: [String: Any] = ["keyPath": "mcp_servers.\(quoted).enabled", "value": enabled,
                                    "mergeStrategy": "replace", "filePath": paths.codexConfig.path]
        if let layer = (settings["layers"] as? [[String: Any]])?.first(where: {
            ($0["name"] as? [String: Any])?["type"] as? String == "user"
        }), let version = layer["version"] as? String { params["expectedVersion"] = version }
        let response = try connection.call("config/value/write", params)
        if response["status"] as? String != "ok" {
            throw LoadoutError.io("Codex 已保存设置，但被另一项配置覆盖了。请在 Codex 里更改那项覆盖它的设置。")
        }
    }

    func setSkill(_ item: Item, in plugin: PluginInfo, enabled: Bool) throws -> URL {
        guard plugin.enabled else { throw LoadoutError.io("先启用 \(plugin.name) 插件，再更改这个技能。") }
        guard item.pluginID == plugin.id, let file = item.path,
              let relative = Self.relative(file, to: plugin.installPath) else { throw LoadoutError.notEditable(item.name) }
        let connection = try CodexConnection(paths: paths)
        defer { connection.close() }
        // Read first: malformed TOML must fail before any write or record change.
        let settings = try connection.call("config/read", ["includeLayers": true])
        if let config = settings["config"] as? [String: Any],
           let plugins = config["plugins"] as? [String: Any],
           let entry = plugins[plugin.nativeKey] as? [String: Any], entry["enabled"] as? Bool == false {
            throw LoadoutError.io("先启用 \(plugin.name) 插件，再更改这个技能。")
        }
        try Backups(paths: paths).snapshot(paths.codexConfig)
        let records = OffRecords(paths: paths)
        let wasRecorded = records.pluginEntries(of: plugin.id).contains(relative)
        if !enabled { try records.rememberPluginEntry(relative, in: plugin.id) }
        let response: [String: Any]
        do {
            response = try connection.call("skills/config/write", ["path": file.path, "enabled": enabled])
        } catch {
            if !enabled && !wasRecorded { try records.forgetPluginEntry(relative, in: plugin.id) }
            throw error
        }
        guard response["effectiveEnabled"] as? Bool == enabled else {
            throw LoadoutError.io("另一项 Codex 设置覆盖了这个技能。请在 Codex 里更改，然后重新载入。")
        }
        if enabled { try records.forgetPluginEntry(relative, in: plugin.id) }
        return file.deletingLastPathComponent()
    }
}
