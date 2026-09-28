import SwiftUI
import AppKit
import LoadoutCore

/// ⌘, opens this. One tab per thing a person occasionally needs to change or look up and would
/// otherwise have no obvious place to find.
struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView {
            AppearanceTab()
                .tabItem { Label("外观", systemImage: "paintpalette") }
            ProjectsTab(model: model)
                .tabItem { Label("项目", systemImage: "folder") }
            UsageTab(model: model)
                .tabItem { Label("使用情况", systemImage: "chart.bar") }
            AssistantsTab(model: model)
                .tabItem { Label("助手", systemImage: "person.2") }
            StorageTab(model: model)
                .tabItem { Label("存储", systemImage: "internaldrive") }
            UpdatesTab()
                .tabItem { Label("更新", systemImage: "arrow.down.circle") }
            HelpTab(model: model)
                .tabItem { Label("帮助", systemImage: "questionmark.circle") }
        }
        .frame(width: 520, height: 400)
    }
}

// MARK: - Reporting a bug

/// One place that knows how to report a bug, because there are two doors to it: the Help tab and
/// the Help menu, which is where macOS has taught everybody to look first.
///
/// What goes with the report is the version, the system, the assistants found and how big the
/// inventory is — the four things a maintainer asks for anyway. Never a file name, never a
/// description, never the contents of anything: the report is about the app, not about the person's
/// work.
@MainActor
enum BugReport {
    static let repository = "https://github.com/migsilva89/loadout"

    static func details(_ model: AppModel) -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let system = ProcessInfo.processInfo.operatingSystemVersion
        // `.plugin` is not a kind of item — plugins are counted on their own — so listing it here
        // printed "plugins: 0" beside the real number.
        let counts = ItemKind.allCases
            .filter { $0 != .plugin }
            .map { kind in "\(kind.briefingNoun)s: \(model.items.filter { $0.kind == kind }.count)" }
            .joined(separator: ", ")
        return """
        Loadout \(version)
        macOS \(system.majorVersion).\(system.minorVersion).\(system.patchVersion)
        Assistants: \(model.assistants.map(\.id).joined(separator: ", "))
        Inventory: \(counts), plugins: \(model.plugins.count)
        """
    }

    static func open(_ model: AppModel) {
        var components = URLComponents(string: "\(repository)/issues/new")!
        components.queryItems = [
            URLQueryItem(name: "template", value: "bug_report.yml"),
            URLQueryItem(name: "labels", value: "bug"),
            URLQueryItem(name: "version", value: Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "dev"),
            URLQueryItem(name: "os", value: ProcessInfo.processInfo.operatingSystemVersionString),
        ]
        guard let url = components.url else { return }
        NSWorkspace.shared.open(url)
    }

    static func openGuide() {
        NSWorkspace.shared.open(URL(string: "\(repository)#readme")!)
    }

    /// The tip jar. The app is free and stays free; this is the one place it says so and asks.
    /// `utm_source` tells the Buy Me a Coffee dashboard which app the visit came from.
    static let coffee = URL(string: "https://buymeacoffee.com/migsilva?utm_source=loadout-app")!

    static func openCoffee() {
        NSWorkspace.shared.open(coffee)
    }
}

// MARK: - Appearance

/// The five themes as five circles, each showing its own accent. No names under them and no
/// menu: the choice is a colour, so the control is the colour — and picking one repaints the
/// window behind this sheet on the spot, which is the only preview worth having.
struct AppearanceTab: View {
    private let themes = ThemeStore.shared
    // The same three keys the reading pane and the ⌘+/− menu use: this is where a person looks for
    // text size, and a preferences window that only holds five circles looks like a placeholder.
    @AppStorage("readerFontSize") private var readerFontSize = 15.0
    @AppStorage("readerFont") private var readerFont = "system"
    @AppStorage("readerBackground") private var readerBackground = "darker"

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    ForEach(ThemeName.allCases) { theme in
                        swatch(theme)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            } header: {
                Text("主题")
            } footer: {
                // Named in words as well, because a ring around a circle says *which* one is on
                // but not what it is called — and the tooltips are the only other place the
                // names appear.
                Text("\(themes.name.hint)。选中后窗口立即变化，下次启动时仍会沿用。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("文字大小") {
                    HStack(spacing: 8) {
                        Slider(value: $readerFontSize, in: 12...22, step: 1)
                            .frame(width: 180)
                            .pointingHand()
                        Text("\(Int(readerFontSize)) pt")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                Picker("字体", selection: $readerFont) {
                    Text("系统").tag("system")
                    Text("衬线").tag("serif")
                    Text("等宽").tag("mono")
                }
                .pointingHand()
                Picker("阅读背景", selection: $readerBackground) {
                    Text("卡片").tag("card")
                    Text("更暗").tag("darker")
                    Text("墨黑").tag("ink")
                }
                .pointingHand()
            } header: {
                Text("阅读")
            } footer: {
                Text("右侧面板里文档的显示方式。在任何地方按 ⌘+ 和 ⌘− 都能调整大小，⌘0 恢复默认。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func swatch(_ theme: ThemeName) -> some View {
        let selected = themes.name == theme
        return Button {
            themes.name = theme
        } label: {
            Circle()
                .fill(theme.palette.accent)
                .frame(width: 26, height: 26)
                // A hairline of its own so Graphite's grey still reads as a disc on the sheet's
                // own grey, and the selected ring sits outside the disc rather than on it.
                .overlay(Circle().strokeBorder(Color.black.opacity(0.25), lineWidth: 0.5))
                .padding(3)
                .overlay {
                    Circle().strokeBorder(
                        selected ? Color.white.opacity(0.9) : Color.clear, lineWidth: 1.5
                    )
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(theme.hint)
        .accessibilityLabel(theme.label)
        .pointingHand()
    }
}

// MARK: - Projects

/// Where Loadout looks for repositories.
///
/// This is the whole of what a person has to keep up to date, and it is deliberately the short
/// list: two or three folders, typed once. What is inside them is worked out on every launch, so
/// a repository cloned this morning is in the list this afternoon with nobody maintaining
/// anything. Before this tab existed the app read one generated file, `~/Projects/INDEX.md`, and
/// anyone without it saw no projects at all.
struct ProjectsTab: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section {
                if model.projectRoots.folders.isEmpty {
                    Text("还没有添加文件夹，所以 Loadout 没有项目可显示，只列出全局加载的内容。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.projectRoots.folders, id: \.self) { folder in
                        HStack {
                            Text(display(folder))
                                .font(.system(size: 12, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                remove(folder)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("不再查找 \(display(folder))")
                            .pointingHand()
                        }
                    }
                }

                HStack {
                    Button("添加文件夹…") { add() }
                        .help("选择存放代码仓库的文件夹，也可以直接选某个仓库")
                        .pointingHand()
                    Spacer()
                    Text(found)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("项目放在哪里")
            } footer: {
                Text(
                    "Loadout 会在这些文件夹里查找代码仓库，也就是含有 .git 或 .claude 的文件夹，"
                    + "最多向下 \(ProjectRoots.searchDepth) 层。文件夹本身是仓库的也算。"
                    + "之后在列表顶部的范围按钮里选中某个项目，就能看到它自己的技能和命令。"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var found: String {
        let count = model.projects.count
        return "找到 \(count) 个项目"
    }

    private func display(_ url: URL) -> String {
        ProjectRoots.abbreviate(url, home: model.paths.home)
    }

    private func add() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "使用此文件夹"
        panel.message = "选择存放代码仓库的文件夹，也可以直接选某个仓库。"
        guard panel.runModal() == .OK else { return }
        // Appended rather than replacing, and a folder chosen twice is not added twice.
        var folders = model.projectRoots.folders
        for url in panel.urls where !folders.contains(where: {
            $0.standardizedFileURL == url.standardizedFileURL
        }) {
            folders.append(url)
        }
        model.setProjectRoots(folders)
    }

    private func remove(_ folder: URL) {
        model.setProjectRoots(model.projectRoots.folders.filter { $0 != folder })
    }
}

// MARK: - Usage

struct UsageTab: View {
    @Bindable var model: AppModel
    @AppStorage("usageWindowDays") private var windowRaw: String = "90"

    private static let options: [(label: String, value: String)] = [
        ("最近 30 天", "30"),
        ("最近 90 天", "90"),
        ("最近一年", "365"),
        ("全部", "all"),
    ]

    private var windowDays: Int? {
        switch windowRaw {
        case "30": return 30
        case "90": return 90
        case "365": return 365
        default: return nil
        }
    }

    var body: some View {
        Form {
            Picker("统计会话的时间范围", selection: $windowRaw) {
                ForEach(Self.options, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .onChange(of: windowRaw) { _, _ in model.reindexUsage(windowDays: windowDays) }
            .help("统计使用次数时往回读取各助手会话的时间范围，保存在这台 Mac 的偏好设置里")
            .pointingHand()

            LabeledContent("已索引的会话", value: "\(model.indexedFileCount)")
            LabeledContent("已索引的事件", value: "\(model.indexedEventCount)")

            Section {
                ForEach(model.usageSources) { source in
                    UsageSourceRow(source: source)
                }
            } header: {
                Text("计数的来源。哪些计入统计由“助手”里的同一个勾选框决定，这里只列出找到了什么。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }

            HStack {
                if model.indexProgress != nil {
                    ProgressView().controlSize(.small)
                    Text("正在重建索引…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("立即重建索引") { model.reindexUsage(windowDays: windowDays) }
                    .disabled(model.indexProgress != nil)
                    .help("按上面选的时间范围，马上重新读取所有助手的会话")
                    .pointingHand(enabled: model.indexProgress == nil)
            }
        }
        // Grouped is what System Settings looks like, and it pins content to the top of the
        // pane instead of floating it in the middle of a fixed-size tab.
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// One history source, and the truth about it. A source with no parser says so rather than sitting
/// at zero looking like an assistant nobody uses.
private struct UsageSourceRow: View {
    let source: UsageSourceStatus

    private var detail: String {
        switch source.state {
        case .included, .excluded:
            let sessions = "\(source.sessionCount) 个会话"
            return "\(source.state.label) · \(sessions) · \(source.eventCount) 个事件"
        case .noHistory, .unsupported, .error:
            return source.state.label
        }
    }

    private var tint: Color {
        switch source.state {
        case .included: return .secondary
        case .excluded, .noHistory, .unsupported: return .secondary.opacity(0.7)
        case .error: return .orange
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(source.label)
            Spacer()
            Text(detail)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .help(help)
    }

    private var help: String {
        switch source.state {
        case .included: return "计入所有使用次数。"
        case .excluded: return "已找到并建立索引，但不计入统计：在“助手”里没有勾选。"
        case .noHistory: return "磁盘上没有这个助手可读取的记录。"
        case .unsupported:
            return "这里有历史记录，但其中没有能证明用过某个技能的内容，所以不计入统计，"
                + "免得显示一个误导人的 0。"
        case .error(let message): return message
        }
    }
}

// MARK: - Updates

/// The visible half of Sparkle: which version is running, whether the daily check is on, when it
/// last got an answer, and a button that asks now.
///
/// Everything here reads and writes Sparkle's own state rather than keeping a copy. Loadout 0.3.2
/// had a pane that stored its own switch and its own "last checked" date, which is how a Settings
/// screen ends up disagreeing with the app it belongs to. Press "Check now" and Sparkle puts up
/// its standard window — the one that shows the release notes and does the installing — so the
/// answer arrives in the place that can act on it.
struct UpdatesTab: View {
    /// Mirrors of Sparkle's preference, because SwiftUI needs something it can observe. `set` on
    /// the binding writes through to the updater; nothing else ever writes this.
    @State private var checksAutomatically = Updates.automaticallyChecksForUpdates
    @State private var lastCheck: Date? = Updates.lastCheck

    var body: some View {
        Form {
            LabeledContent("版本", value: Updates.current ?? "未发布的构建")

            Toggle("自动检查更新", isOn: Binding(
                get: { checksAutomatically },
                set: { newValue in
                    checksAutomatically = newValue
                    Updates.automaticallyChecksForUpdates = newValue
                }
            ))
            .help(
                "大约每天向发布源询问一次有没有新版本，有就提示你安装。"
                    + "不会发送任何文件或标识信息。关掉后，Loadout 完全不联网。"
            )

            LabeledContent("上次检查", value: lastCheckLine)

            HStack {
                Spacer()
                Button("立即检查") { check() }
                    .help("马上检查一次，不管自动检查有没有打开")
                    .pointingHand()
            }

            Text(
                "更新由 Loadout 自己下载并安装。只有用构建这份副本时的同一把密钥签名的更新才会被接受，"
                    + "被篡改过的下载会被拒绝，不会安装。"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Sparkle has no date until the first check completes, and "Never" is a truer answer for a
    /// fresh install than a date invented to fill the row.
    private var lastCheckLine: String {
        guard let lastCheck else { return "从未" }
        return lastCheck.formatted(date: .abbreviated, time: .shortened)
    }

    /// Sparkle owns the window that follows, so there is nothing to show in the pane afterwards —
    /// only the date to catch up with, once the check has had a moment to land.
    private func check() {
        Updates.checkNow()
        Task {
            try? await Task.sleep(for: .seconds(2))
            lastCheck = Updates.lastCheck
        }
    }
}

// MARK: - Assistants

/// The pane behind Settings › Assistants.
///
/// Written as `SettingsGroup` cards like every other section: this was a `List` with an infinite
/// height, and a list that asks for all the height there is renders nothing at all inside the
/// pane's scroll view — the section counted 12 assistants in the sidebar and then showed an empty
/// page.
struct AssistantsTab: View {
    @Bindable var model: AppModel

    var body: some View {
        SettingsGroup(
            title: "助手",
            note: "勾选的助手会显示在列表行和详情面板里，它的会话也计入使用次数。"
                + "取消勾选则两样都停：从列表里消失，也不再计数。",
            footnote: "不会删除任何东西，重新勾选后原来的数字都会回来。"
                + "无论勾不勾选，共享和同步都照常工作。"
        ) {
            ForEach(Array(model.assistants.enumerated()), id: \.element.id) { index, assistant in
                AssistantSettingsRow(
                    model: model,
                    assistant: assistant,
                    dividing: index < model.assistants.count - 1
                )
            }
        }

        SettingsGroup(
            title: "提问用的 CLI",
            note: "技能详情里的“提问”会运行这些命令。五个内置的装好后会自动出现，"
                + "其他的可以手动添加。"
        ) {
            ForEach(model.assistantCLIs) { cli in
                AskCLIRow(model: model, cli: cli)
            }
            SettingsRow(
                label: "添加自己的 CLI",
                sub: "任何接受 prompt 的命令都可以交给 Loadout",
                dividing: false
            ) {
                Button("添加…") { model.isAddingAssistantCLI = true }
                    .buttonStyle(V2ToolbarButtonStyle(prominent: false, enabled: true))
                    .pointingHand()
            }
        }
    }
}

/// One assistant CLI in Settings › Assistants › Ask CLIs: its resolved path, whether it's a
/// built-in or something the owner added, and a way to try it without leaving the sheet.
private struct AskCLIRow: View {
    @Bindable var model: AppModel
    let cli: AssistantCLI
    @State private var testing = false
    @State private var testResult: String?

    private var displayPath: String {
        cli.executable.path.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"
        )
    }

    private var customEntry: CustomAssistantCLI? {
        model.customAssistantCLIs.first { $0.id == cli.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(cli.label)
                        Text(cli.isCustom ? "自定义" : "内置")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                    Text(displayPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if testing { ProgressView().controlSize(.small) }
                Button("测试") { test() }
                    .disabled(testing)
                    .help("用一个简单的 prompt（“reply with OK”）真正运行一次 \(cli.label)，看它能不能用")
                    .pointingHand(enabled: !testing)
                if let customEntry {
                    Button("编辑") { model.editingCustomAssistantCLI = customEntry }
                        .pointingHand()
                    Button("移除") { model.removeCustomAssistantCLI(customEntry) }
                        .pointingHand()
                }
            }
            if let testResult {
                Text(testResult)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Hairline(color: Color.white.opacity(0.06)).padding(.leading, 14)
        }
    }

    private func test() {
        testing = true
        testResult = nil
        let copilot = model.copilot
        let target = cli
        let directory = FileManager.default.temporaryDirectory

        Task.detached(priority: .userInitiated) {
            do {
                let result = try copilot.run(cli: target, prompt: "reply with OK", in: directory, timeout: 30)
                await MainActor.run {
                    let firstLine = result.output.split(separator: "\n").first.map(String.init) ?? "（无输出）"
                    testResult = result.timedOut
                        ? "超时。"
                        : "退出码 \(result.exitCode)：\(firstLine)"
                    testing = false
                }
            } catch {
                await MainActor.run {
                    testResult = (error as? LoadoutError)?.errorDescription ?? error.localizedDescription
                    testing = false
                }
            }
        }
    }
}

private struct AssistantSettingsRow: View {
    @Bindable var model: AppModel
    let assistant: Assistant
    /// The last row in a card draws no separator — a line under it would point at nothing.
    var dividing = true

    private var skillCount: Int {
        model.items.filter { $0.kind == .skill && $0.assistants.contains(assistant.id) }.count
    }

    private var skillsPath: String {
        assistant.skillsRoot.path.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"
        )
    }

    var body: some View {
        HStack(spacing: 10) {
            AssistantMark(assistant: assistant, present: true, size: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(assistant.label)
                Text(skillsPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(skillCount) 个技能")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Toggle("显示并计数", isOn: Binding(
                get: { !model.hiddenAssistantIDs.contains(assistant.id) },
                set: { model.setAssistantHidden(assistant, hidden: !$0) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .help(
                "在列表行和详情面板里显示 \(assistant.label)，并把它的会话计入使用次数。"
                    + "取消勾选会隐藏它并停止计数。不会删除任何东西，重新勾选后原来的数字都会回来。"
                    + "无论勾不勾选，共享和同步都照常工作。"
            )
            .pointingHand()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            if dividing { Hairline(color: Color.white.opacity(0.06)).padding(.leading, 14) }
        }
    }
}

// MARK: - Backups

struct StorageTab: View {
    @Bindable var model: AppModel
    @State private var isCounting = false
    @State private var report = Housekeeping.Report()
    @State private var isDeleting = false
    @State private var confirmingDelete = false
    @State private var resultMessage: String?

    var body: some View {
        Form {
            Section {
                if isCounting {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("正在统计…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    LabeledContent("快照", value: "\(report.snapshots)")
                    LabeledContent(
                        "占用空间",
                        value: ByteCountFormatter.string(fromByteCount: report.bytes, countStyle: .file)
                    )
                    if report.strandedRecords > 0 {
                        LabeledContent("已不存在的内容留下的记录", value: "\(report.strandedRecords)")
                    }
                }

                HStack {
                    Button("在访达中显示") { model.revealBackups() }
                        .help("在访达中显示 \(model.paths.backups.path)")
                        .pointingHand()
                    Spacer()
                    Button("立即清理") { confirmingDelete = true }
                        .disabled(isDeleting || isCounting || report.isEmpty)
                        .help(
                            report.isEmpty
                                ? "现在没有需要清理的内容"
                                : "清掉超过 30 天的快照，以及已不存在的内容留下的记录"
                        )
                        .pointingHand(enabled: !(isDeleting || isCounting || report.isEmpty))
                }

                if let resultMessage {
                    Text(resultMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Loadout 保存的内容")
            } footer: {
                Text(
                    "每次编辑前 Loadout 都会先复制一份文件，所以改错了也能挽回。"
                    + "超过 30 天的副本会在启动时自动移到废纸篓，清倒废纸篓之前都不会真的消失。"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if !report.unreadableRecords.isEmpty {
                Section {
                    ForEach(report.unreadableRecords, id: \.self) { url in
                        Text(url.lastPathComponent)
                            .font(.system(size: 12, design: .monospaced))
                    }
                    Button("在访达中显示") { model.revealBackups() }
                        .pointingHand()
                } header: {
                    Text("无法读取")
                } footer: {
                    // Never swept: an unreadable file is a question, and deleting it answers it
                    // the wrong way. Something switched off may be recorded in here.
                    Text(
                        "这些是 Loadout 自己的记录，里面可能记着某些已停用的内容。"
                        + "原因查明之前不会清理它们，免得丢东西。"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task { await recount() }
        .alert("立即清理？", isPresented: $confirmingDelete) {
            Button("取消", role: .cancel) {}
            Button("清理", role: .destructive) { Task { await sweep() } }
        } message: {
            Text(
                "超过 30 天的备份副本会移到废纸篓，已不存在的内容留下的记录会被清除。"
                + "你写的内容不会被动到。"
            )
        }
    }

    private func recount() async {
        isCounting = true
        let housekeeping = Housekeeping(paths: model.paths)
        // Sizing every snapshot is not cheap, so it runs off the main thread — the whole reason
        // this is a task rather than a computed property.
        report = await Task.detached(priority: .utility) { housekeeping.report() }.value
        isCounting = false
    }

    private func sweep() async {
        isDeleting = true
        let housekeeping = Housekeeping(paths: model.paths)
        let done = await Task.detached(priority: .utility) {
            (try? housekeeping.sweep()) ?? Housekeeping.Report()
        }.value
        resultMessage = describe(done)
        isDeleting = false
        await recount()
    }

    private func describe(_ done: Housekeeping.Report) -> String {
        var parts: [String] = []
        if done.expiredSnapshots > 0 {
            parts.append("\(done.expiredSnapshots) 个快照")
        }
        if done.strandedRecords > 0 {
            parts.append("\(done.strandedRecords) 条记录")
        }
        return parts.isEmpty ? "没有需要清理的内容。" : "已清理 " + parts.joined(separator: "和 ") + "。"
    }
}

// MARK: - Help

/// What the app does to your files, where it keeps its own, and how to report it when it gets
/// something wrong.
///
/// An app that moves folders around inside `~/.claude` owes the person using it a plain account of
/// what "off" actually does — kept here rather than in a README nobody opens, because the question
/// arrives while the app is in front of you. The bug report is prefilled with what a maintainer
/// always has to ask for anyway, and is shown before it is sent: nothing leaves without being read.
struct HelpTab: View {
    @Bindable var model: AppModel
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                section("停用某项时会发生什么") {
                    line("技能", "移到所属助手旁边的 `skills-off` 文件夹，绝不会移进别的助手的目录。重新启用时会问你要让哪些助手再次加载它。")
                    line("命令或子代理", "移到旁边的 `commands-off` 或 `agents-off`。")
                    line("插件里的技能", "Claude 的技能在已安装的插件内部挪到一旁。Codex 的技能用 Codex 自己的启用设置。插件更新后，Loadout 会保留你对单项的停用选择。")
                    line("整个插件", "列表里它的所有技能都会停用，但不会忘记你对单项的选择。重新启用插件就能恢复这些选择。由工作区管理的 Codex 插件要在 Codex 里修改。")
                    line("MCP 服务器", "它的条目会从 ~/.claude.json 里取出并保存好，之后原样放回。")
                    line("不会删除任何东西", "每次写入前都会先备份。删除是另一个单独的操作，删掉的东西会进废纸篓。")
                }

                section("Loadout 自己的文件放在哪里") {
                    pathRow(model.paths.support)
                    Text("备份、使用情况索引，以及已停用内容的记录。特意不放在 ~/.claude 里，那是 Claude Code 的地方。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                section("出问题时") {
                    Text(diagnostics)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    HStack {
                        Button("报告问题") { BugReport.open(model) }
                            .help("在 GitHub 上新建一个 issue，版本和系统信息已经填好")
                            .pointingHand()
                        Button(copied ? "已拷贝" : "拷贝这些信息") { copyDiagnostics() }
                            .help("拷贝上面几行，粘贴到你报告问题的地方")
                            .pointingHand()
                        Spacer()
                        Button("打开使用指南") { BugReport.openGuide() }
                        .help("README，介绍这个 App 能做什么、是怎么做的")
                        .pointingHand()
                    }
                }

                section("免费，而且一直免费") {
                    HStack(spacing: 8) {
                        Text("如果 Loadout 帮你省了时间，一杯咖啡能让下个版本更快到来。")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                        Button("请我喝杯咖啡 ☕") { BugReport.openCoffee() }
                            .help("在浏览器中打开 buymeacoffee.com")
                            .pointingHand()
                    }
                }
            }
            .padding(18)
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            content()
        }
    }

    private func line(_ subject: String, _ rest: String) -> some View {
        // `.init` so the whole sentence is read as markdown: interpolating a `LocalizedStringKey`
        // into a plain string prints the key's own description, brackets and all.
        Text(.init("**\(subject)**：\(rest)"))
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func pathRow(_ url: URL) -> some View {
        HStack(spacing: 8) {
            Text(url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            Button("在访达中显示") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                .buttonStyle(.link)
                .help("在访达中打开这个文件夹")
                .pointingHand()
        }
    }

    private var diagnostics: String { BugReport.details(model) }

    private func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnostics, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
    }

}
