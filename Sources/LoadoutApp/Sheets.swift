import SwiftUI
import AppKit
import UniformTypeIdentifiers
import LoadoutCore

/// Create a skill, a command or a subagent — and, by default, have an assistant write it.
///
/// It used to be the other way round: "Create" carried Enter and made an empty folder, while
/// "Create and ask" sat beside it as the curiosity. That had the shape backwards. Nobody
/// hand-writes a skill any more, and the hard part was never the folder — it is the description
/// that decides whether the thing is ever reached for, and a body worth loading.
///
/// So the assistant carries Enter, and the second field changed meaning with it. It used to ask for
/// the description and advise how to write one; asking somebody to write a good description before
/// an assistant rewrites it is asking twice. It is a brief now: plain sentences about what they
/// want. The old wording comes back only in the one case where nobody downstream will sharpen it —
/// no assistant installed at all.
struct NewSkillSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var brief = ""
    @State private var chosenCLI: AssistantCLI?
    @State private var pickerOpen = false
    @FocusState private var focus: Field?

    private enum Field { case name, brief }

    /// The Commands and Agents tabs make their own kinds here, with the same name rules and the
    /// same refusal to overwrite. Only the words and the file written change.
    private var makesCommand: Bool { model.selection == .commands }
    private var makesAgent: Bool { model.selection == .agents }
    private var noun: String { makesAgent ? "子代理" : (makesCommand ? "命令" : "技能") }

    /// The assistants that can be asked. Empty is a real state on a fresh Mac, and the sheet
    /// changes shape for it rather than showing a button that can only apologise.
    private var clis: [AssistantCLI] { model.askableCLIs }
    private var assistant: AssistantCLI? {
        chosenCLI ?? clis.first { $0.id == model.lastAssistantCLIID } ?? clis.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                heading
                field(
                    label: "名称",
                    hint: nameHint,
                    bad: !name.isEmpty && !isNameValid
                ) { nameInput }
                field(label: briefLabel, hint: briefHint, bad: false, optional: assistant != nil) {
                    briefInput
                }
                if assistant == nil { noAssistantNote }
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 20)

            footer
        }
        .frame(width: 520)
        .background(V2.popover)
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.13), lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onAppear { focus = .name }
    }

    // MARK: - Heading

    /// The subtitle says what the thing will be before anything is asked of you — the same lesson
    /// the welcome sheet learned. "Personal skill" is a fact somebody would otherwise discover
    /// after the fact, in the Details card.
    private var heading: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("新建\(noun)")
                .font(.system(size: 16, weight: .semibold))
                .tracking(-0.2)
            Text(subtitle)
                .font(.system(size: 12.5))
                .foregroundStyle(Color.white.opacity(0.45))
        }
    }

    private var subtitle: String {
        if makesCommand { return "输入名字才会运行，它不会自己触发" }
        if makesAgent { return "助手决定分派时，会按名字把活交给它" }
        return "个人技能 · 在每个项目中加载"
    }

    // MARK: - Fields

    private func field<Control: View>(
        label: String, hint: String, bad: Bool, optional: Bool = false,
        @ViewBuilder control: () -> Control
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.60))
                if optional {
                    Text("可选")
                        .font(.system(size: 11))
                        .foregroundStyle(V2.textFaint)
                }
            }
            control()
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                if bad {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 10.5))
                }
                Text(hint)
            }
            .font(.system(size: 11.5))
            .foregroundStyle(bad ? V2.issue : Color.white.opacity(0.42))
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var nameInput: some View {
        HStack(spacing: 0) {
            // The slash is drawn into the field rather than typed, so the name reads the way it
            // will be used — and so nobody types it and ends up with a file called "/deploy".
            if makesCommand {
                Text("/")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.38))
            }
            TextField(makesAgent ? "agent-name" : (makesCommand ? "command-name" : "skill-name"), text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .focused($focus, equals: .name)
        }
        .padding(.horizontal, 11)
        .frame(height: 30)
        .background(inputFill(bad: !name.isEmpty && !isNameValid, focused: focus == .name))
    }

    private var briefInput: some View {
        TextField(briefPlaceholder, text: $brief, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .lineSpacing(3)
            .focused($focus, equals: .brief)
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .frame(minHeight: 88, alignment: .topLeading)
            .background(inputFill(bad: false, focused: focus == .brief))
    }

    /// One fill, one border, one ring — so a focused field and a wrong one are told apart by colour
    /// rather than by two different shapes.
    private func inputFill(bad: Bool, focused: Bool) -> some View {
        let edge: Color = bad ? V2.issue : (focused ? V2.accent : Color.white.opacity(0.12))
        return RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.black.opacity(0.28))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(edge, lineWidth: bad || focused ? 1 : 0.5)
            }
            .overlay {
                if bad || focused {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder((bad ? V2.issue : V2.accent).opacity(0.22), lineWidth: 3)
                        .padding(-2)
                }
            }
    }

    // MARK: - Copy that changes with the state

    private var briefLabel: String {
        // With nobody to sharpen it, the field goes back to being the description it will really be,
        // and the advice for writing one comes back with it.
        guard assistant != nil else { return "描述" }
        if makesCommand { return "运行它时应该做什么？" }
        if makesAgent { return "这个子代理应该擅长什么？" }
        return "你想让这个技能做什么？"
    }

    /// Never the label again. A placeholder repeating the words directly above it wastes the one
    /// chance to show what a good answer looks like.
    private var briefPlaceholder: String {
        if makesCommand { return "读取上一个 tag 之后合并的 PR，然后发布说明" }
        if makesAgent { return "审查 SQL 迁移里的锁表和回滚问题" }
        return "把合并的 pull request 整理成发布说明，跳过重构"
    }

    private var briefHint: String {
        guard let assistant else {
            return "写清楚什么时候该用它，而不是它是什么。助手挑选时读的就是这段。"
        }
        // Named when there is one, because the button names it too and repeating it costs nothing.
        // "The assistant" when there are several, since the choice is not made until the button.
        // Lowercase, because every use of it here is mid-sentence: "and The assistant asks you"
        // is the kind of seam that makes copy look generated.
        // The trailing space only on the English name, so "Claude Code 会" and "助手会" both read right.
        let who = clis.count == 1 ? "\(assistant.label) " : "助手"
        if brief.trimmingCharacters(in: .whitespaces).isEmpty {
            return "留空的话，\(who)会先问你几个问题，而不是瞎猜。"
        }
        if makesCommand {
            return "\(who)会写出这条命令要运行的提示词。说清楚它该做什么、"
                + "接受哪些参数。"
        }
        return "\(who)会把这段话改写成能在恰当时机触发的描述，并写好"
            + "正文。用平常的话写就够了。"
    }

    private var nameHint: String {
        if name.isEmpty {
            return "只能用小写字母、数字和连字符。"
                + (makesCommand ? "这就是你在斜杠后输入的名字。" : (makesAgent ? "它会成为文件名。" : "它会成为文件夹名。"))
        }
        guard isNameValid else {
            // The fixed form, spelled out: telling somebody the rule and letting them apply it is
            // more work than showing them the answer.
            return "不能有空格或大写字母。试试 \(suggestedName)。"
        }
        if makesAgent {
            return model.context.map { "\($0.name)/.claude/agents/\(name).md" }
                ?? "~/.claude/agents/\(name).md"
        }
        if makesCommand {
            return model.context.map { "\($0.name)/.claude/commands/\(name).md" }
                ?? "~/.claude/commands/\(name).md"
        }
        return "~/.claude/skills/\(name)/SKILL.md"
    }

    private var suggestedName: String {
        let lowered = name.lowercased()
            .map { ($0.isLetter && $0.isASCII) || $0.isNumber ? $0 : "-" }
        return String(lowered)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
    }

    private var noAssistantNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 11.5))
                .foregroundStyle(V2.textMid)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text("这台 Mac 上没找到编程助手，所以没有谁能替你写。")
                HStack(spacing: 4) {
                    Button("助手设置") {
                        model.settingsSection = "assistants"
                        model.showsSettings = true
                        dismiss()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(V2.link)
                    .help("打开设置，查看 Loadout 会查找哪些助手")
                    .pointingHand()
                    Text("里列出了 Loadout 会查找的助手。")
                }
            }
            .font(.system(size: 11.5))
            .foregroundStyle(V2.textMid)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(V2.hairline, lineWidth: 0.5)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Button("取消") { dismiss() }
                .buttonStyle(SheetButtonStyle(kind: .quiet, enabled: true))
                .keyboardShortcut(.cancelAction)
                .help("关闭，不创建\(noun)")
                .pointingHand()

            Spacer(minLength: 12)

            if assistant == nil {
                // Nothing to contrast against, so "empty" would only sound like a lesser choice.
                Button { createOnly() } label: { primaryLabel(text: "创建\(noun)", badge: nil) }
                    .buttonStyle(SheetButtonStyle(kind: .primary, enabled: isNameValid))
                    .disabled(!isNameValid)
                    .keyboardShortcut(.defaultAction)
                    .help("创建\(noun)并打开编辑")
                    .pointingHand(enabled: isNameValid)
            } else {
                Button("创建空白") { createOnly() }
                    .buttonStyle(SheetButtonStyle(kind: .quiet, enabled: isNameValid))
                    .disabled(!isNameValid)
                    .help("只创建\(noun)并打开，什么都不写")
                    .pointingHand(enabled: isNameValid)
                assistantAction
            }
        }
        .padding(.leading, 24)
        .padding(.trailing, 18)
        .padding(.vertical, 13)
        .background(Color.black.opacity(0.20))
        .overlay(alignment: .top) { Hairline(color: V2.hairline) }
    }

    /// One assistant: a plain button naming it. Several: the same button with a chevron beside it,
    /// because the choice of *which* belongs on the button that uses it — in a picker above the
    /// fields it read as part of the thing being made.
    @ViewBuilder
    private var assistantAction: some View {
        if let assistant {
            HStack(spacing: 0) {
                Button { createAndAsk(assistant) } label: {
                    primaryLabel(text: "用 \(assistant.label) 编写", badge: assistant)
                }
                .buttonStyle(SheetButtonStyle(
                    kind: .primary, enabled: isNameValid, rightSquare: clis.count > 1
                ))
                .disabled(!isNameValid)
                .keyboardShortcut(.defaultAction)
                .help("创建\(noun)，再让 \(assistant.label) 写好内容，由你决定是否采纳")
                .pointingHand(enabled: isNameValid)

                if clis.count > 1 {
                    Button { pickerOpen = true } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 9)
                            .frame(height: 30)
                    }
                    .buttonStyle(SheetButtonStyle(kind: .primaryTrailing, enabled: isNameValid))
                    .disabled(!isNameValid)
                    .help("选择由哪个助手来写")
                    .pointingHand(enabled: isNameValid)
                    .popover(isPresented: $pickerOpen, arrowEdge: .bottom) { assistantMenu }
                }
            }
        }
    }

    private func primaryLabel(text: String, badge: AssistantCLI?) -> some View {
        HStack(spacing: 7) {
            if let badge { cliBadge(badge) }
            Text(text)
                .font(.system(size: 13, weight: .medium))
            // Absent when the button does nothing: an Enter hint on an unavailable action is a
            // promise the keyboard will not keep.
            if isNameValid {
                Text("↵")
                    .font(.system(size: 11.5))
                    .opacity(0.6)
            }
        }
    }

    private func cliBadge(_ cli: AssistantCLI) -> some View {
        Text(Self.initials(cli.label))
            .font(.system(size: 8, weight: .semibold, design: .rounded))
            .frame(width: 16, height: 16)
            .background(
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .fill(Color.white.opacity(0.22))
            )
    }

    /// One letter per word — "Claude Code" is CC, not CL. Taking the first two letters of the
    /// whole name made two different assistants collide as often as it identified one.
    private static func initials(_ label: String) -> String {
        let words = label.split(separator: " ")
        guard words.count > 1 else { return String(label.prefix(2)).uppercased() }
        return words.prefix(2).map { String($0.prefix(1)).uppercased() }.joined()
    }

    private var assistantMenu: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("用谁来写")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(V2.textFaint)
                .padding(.horizontal, 9)
                .padding(.top, 6)
                .padding(.bottom, 3)

            ForEach(clis) { cli in
                let current = cli.id == assistant?.id
                Button {
                    chosenCLI = cli
                    pickerOpen = false
                } label: {
                    HStack(spacing: 8) {
                        cliBadge(cli)
                            .opacity(current ? 1 : 0.8)
                        Text(cli.label)
                            .font(.system(size: 12.5))
                        Spacer(minLength: 8)
                        if current {
                            Text("↵")
                                .font(.system(size: 11))
                                .opacity(0.7)
                        }
                    }
                    .foregroundStyle(current ? Color.white : V2.text)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(current ? V2.accent : Color.clear)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHand()
            }

            Hairline(color: V2.hairline).padding(.vertical, 4)
            Text("会记住你上次的选择。")
                .font(.system(size: 11.5))
                .foregroundStyle(V2.textFaint)
                .padding(.horizontal, 9)
                .padding(.bottom, 6)
        }
        .padding(5)
        .frame(width: 250)
    }

    // MARK: - Doing it

    private func createOnly() {
        if makesCommand || makesAgent {
            model.createCommand(name: name, description: brief, kind: makesAgent ? .agent : .command)
        } else {
            model.createSkill(name: name, description: brief)
        }
        dismiss()
    }

    private func createAndAsk(_ cli: AssistantCLI) {
        if makesCommand || makesAgent {
            model.createCommandAndAsk(
                name: name, brief: brief, kind: makesAgent ? .agent : .command, cli: cli
            )
        } else {
            model.createSkillAndAsk(name: name, description: brief, cli: cli)
        }
        dismiss()
    }

    private var isNameValid: Bool { isValidSkillName(name) }
}

/// The buttons on a sheet: one quiet, one filled, and the filled one's trailing half when it has a
/// chevron beside it.
///
/// Written rather than taken from AppKit because every other surface in this app draws its own, and
/// a stock button in the middle of one announces that the panel was assembled from parts. A
/// disabled primary keeps the accent at 28%: still legible as the way forward once the name is
/// fixed, rather than a grey slab that reads as gone.
struct SheetButtonStyle: ButtonStyle {
    enum Kind { case quiet, primary, primaryTrailing }

    let kind: Kind
    let enabled: Bool
    /// True when a chevron sits against this button's right edge, so the corners meet flush.
    var rightSquare = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(label(pressed: configuration.isPressed))
            .padding(.horizontal, kind == .primaryTrailing ? 0 : 13)
            .frame(height: 30)
            .background(shape(pressed: configuration.isPressed))
    }

    private func label(pressed: Bool) -> Color {
        switch kind {
        case .quiet:
            return enabled ? V2.text : Color.white.opacity(0.28)
        case .primary, .primaryTrailing:
            return enabled ? .white : Color.white.opacity(0.30)
        }
    }

    @ViewBuilder
    private func shape(pressed: Bool) -> some View {
        let corners = RoundedRectangle(cornerRadius: 8, style: .continuous)
        switch kind {
        case .quiet:
            corners
                .fill(enabled && pressed ? V2.buttonHover : V2.button)
                .overlay { corners.strokeBorder(V2.hairline, lineWidth: 0.5) }
        case .primary:
            UnevenRoundedRectangle(
                topLeadingRadius: 8, bottomLeadingRadius: 8,
                bottomTrailingRadius: rightSquare ? 0 : 8, topTrailingRadius: rightSquare ? 0 : 8,
                style: .continuous
            )
                .fill(V2.accent.opacity(enabled ? (pressed ? 0.85 : 1) : 0.28))
        case .primaryTrailing:
            UnevenRoundedRectangle(
                topLeadingRadius: 0, bottomLeadingRadius: 0,
                bottomTrailingRadius: 8, topTrailingRadius: 8, style: .continuous
            )
                .fill(V2.accent.opacity(enabled ? (pressed ? 0.85 : 1) : 0.28))
                .overlay(alignment: .leading) {
                    Rectangle().fill(Color.black.opacity(0.35)).frame(width: 0.5)
                }
                .overlay(Color.black.opacity(0.12))
        }
    }
}

/// Ask an assistant CLI about the selected skill (AC7). Nothing is written without a decision
/// here — the sheet only ever shows text back, whichever assistant produced it.
struct CopilotSheet: View {
    @Bindable var model: AppModel
    let cli: AssistantCLI
    @Environment(\.dismiss) private var dismiss
    @State private var prompt = "Improve this skill's description so it triggers at the right times, and explain what you changed."
    @State private var answer = ""
    @State private var running = false
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("向 \(cli.label) 提问")
                .font(.title3.weight(.semibold))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $prompt)
                .font(.system(size: 12))
                .frame(height: 70)
                .padding(6)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            ScrollView {
                Text(answer.isEmpty ? "回答会显示在这里。你决定之前，什么都不会写入。" : answer)
                    .font(.system(size: 12, design: answer.isEmpty ? .default : .monospaced))
                    .foregroundStyle(answer.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(height: 260)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))

            HStack {
                if running { ProgressView().controlSize(.small) }
                Spacer()
                Button("关闭") {
                    model.copilot.cancel()
                    dismiss()
                }
                .help("关闭，不保存任何内容")
                .pointingHand()
                if running {
                    Button("取消") { model.copilot.cancel() }
                        .help("停止正在发给 \(cli.label) 的请求")
                        .pointingHand()
                } else {
                    Button("提问") { ask() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(prompt.trimmingCharacters(in: .whitespaces).isEmpty)
                        .help("在技能文件夹中用这段提示运行 \(cli.invocationDescription)（⌘↵）")
                        .pointingHand(
                            enabled: !prompt.trimmingCharacters(in: .whitespaces).isEmpty
                        )
                }
                Button("拷贝回答") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(answer, forType: .string)
                }
                .disabled(answer.isEmpty)
                .help("将 \(cli.label) 的回答拷贝到剪贴板")
                .pointingHand(enabled: !answer.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 620)
    }

    private var subtitle: String {
        guard let item = model.selected else { return "" }
        return "在 \(item.name) 文件夹中运行 \(cli.invocationDescription)。"
    }

    private func ask() {
        guard let item = model.selected,
              let directory = item.directory ?? item.path?.deletingLastPathComponent()
        else { return }
        running = true
        failure = nil
        answer = ""
        let copilot = model.copilot
        let question = prompt
        let target = cli

        Task.detached(priority: .userInitiated) {
            do {
                let result = try copilot.run(cli: target, prompt: question, in: directory)
                await MainActor.run {
                    answer = result.output
                    failure = result.timedOut ? "请求超时，已停止。" : nil
                    running = false
                }
            } catch {
                await MainActor.run {
                    failure = (error as? LoadoutError)?.errorDescription ?? error.localizedDescription
                    running = false
                }
            }
        }
    }
}

/// Add or edit a custom assistant CLI (Settings › Assistants › Ask CLIs). Built-ins never open
/// this sheet — they're read-only there.
struct AssistantCLIFormSheet: View {
    @Bindable var model: AppModel
    /// `nil` means "Add…"; otherwise this is the entry being edited.
    let editing: CustomAssistantCLI?
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var path: String
    @State private var template: String
    @State private var failure: String?

    init(model: AppModel, editing: CustomAssistantCLI?) {
        self.model = model
        self.editing = editing
        _name = State(initialValue: editing?.label ?? "")
        _path = State(initialValue: editing?.executablePath ?? "")
        _template = State(initialValue: editing?.argumentTemplate ?? "{prompt}")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(editing == nil ? "添加助手 CLI" : "编辑助手 CLI")
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 5) {
                Text("名称").font(.caption).foregroundStyle(.secondary)
                TextField("Gemini", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("命令").font(.caption).foregroundStyle(.secondary)
                HStack {
                    TextField("/usr/local/bin/gemini", text: $path)
                        .textFieldStyle(.roundedBorder)
                    Button("选择…") { choosePath() }
                        .help("在这台 Mac 上找到助手程序，不用手动输入路径")
                        .pointingHand()
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("参数").font(.caption).foregroundStyle(.secondary)
                TextField("-p {prompt}", text: $template)
                    .textFieldStyle(.roundedBorder)
                Text("在问题要放的位置写 {prompt}，例如“-p {prompt}”或“exec {prompt}”。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .help("关闭，不保留这里输入的内容")
                    .pointingHand()
                Button(editing == nil ? "添加" : "保存") { save() }
                    .keyboardShortcut(.defaultAction)
                    .help(
                        editing == nil
                            ? "把它加到可以就技能提问的助手里"
                            : "保存对这个助手运行方式的修改"
                    )
                    .pointingHand()
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func choosePath() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.allowedContentTypes = [.unixExecutable]
        panel.title = "选择助手的可执行文件"
        if panel.runModal() == .OK, let url = panel.url {
            path = url.path
        }
    }

    private func save() {
        do {
            if let editing {
                try model.updateCustomAssistantCLI(editing, name: name, path: path, template: template)
            } else {
                try model.addCustomAssistantCLI(name: name, path: path, template: template)
            }
            dismiss()
        } catch {
            failure = (error as? LoadoutError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// Where a skill goes when it comes back on (AC3.5).
///
/// Switching off is one gesture with one meaning; switching on is a choice, because the app cannot
/// know for someone which assistants should load a skill again. The ticks start from what Loadout
/// recorded when it was switched off, so confirming without touching anything is a plain undo.
struct RestoreSkillSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("启用 \(model.restoring?.item.name ?? "")")
                .font(.title3.weight(.semibold))

            Text(
                model.restoring?.remembered == true
                    ? "你停用它的时候，是这些助手在加载它。"
                    : "Loadout 判断不出这个技能以前在哪里加载，所以先按它现在停放的位置来建议。"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(model.visibleAssistants) { assistant in
                    Toggle(assistant.label, isOn: binding(for: assistant))
                        .toggleStyle(.checkbox)
                        .help("勾选后，\(assistant.label) 会重新加载这个技能")
                        .pointingHand()
                }
            }

            Text(chosenCount > 1
                ? "文件夹放到 ~/.agents/skills，每个助手各有一个指向它的链接。只有一份，改一处就行。"
                : "文件夹直接放进那个助手，其他地方不留链接。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .help("让技能保持停用")
                    .pointingHand()
                Button("启用") {
                    model.confirmRestore()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(chosenCount == 0)
                .help("把技能放回上面勾选的助手")
                .pointingHand(enabled: chosenCount > 0)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private var chosenCount: Int { model.restoring?.chosen.count ?? 0 }

    private func binding(for assistant: Assistant) -> Binding<Bool> {
        Binding(
            get: { model.restoring?.chosen.contains(assistant.id) ?? false },
            set: { on in
                guard var restoring = model.restoring else { return }
                if on { restoring.chosen.insert(assistant.id) } else { restoring.chosen.remove(assistant.id) }
                model.restoring = restoring
            }
        )
    }
}

/// The one-time note that disabling a project skill shows up in the repository (AC3.20).
///
/// Loadout runs no git commands and knows nothing about version control. It moves a folder — but
/// that folder lives inside a repository, so the change lands next to whatever work is in progress
/// and could be committed without anyone meaning to. Worth saying once; not worth saying twice.
/// Uninstalling a plugin, asked and answered in one place — the same two-state dialog the
/// make-global note uses, for the same reason: the click has consequences in three files, and the
/// only honest place to report them is the thing that asked.
struct RemovePluginSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private var plugin: PluginInfo? { model.pendingPluginRemoval }
    private var done: Bool { model.pluginRemovalDone || model.pluginRemovalError != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                if done {
                    Image(systemName: model.pluginRemovalError == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(model.pluginRemovalError == nil ? Color.green : Color.orange)
                }
                Text(title)
                    .font(.title3.weight(.semibold))
            }
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let plugin, !done {
                Text(model.readablePath(of: plugin))
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            HStack {
                Spacer()
                if done {
                    Button("完成") { close() }
                        .keyboardShortcut(.defaultAction)
                        .pointingHand()
                } else {
                    Button("取消") { close() }
                        .keyboardShortcut(.cancelAction)
                        .help("保留这个插件")
                        .pointingHand()
                    Button("移到废纸篓") { model.confirmRemovePlugin() }
                        .keyboardShortcut(.defaultAction)
                        .help("卸载它：文件夹移到废纸篓，条目从 Claude Code 的登记表中移除")
                        .pointingHand()
                }
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func close() {
        model.dismissPluginRemoval()
        dismiss()
    }

    private var title: String {
        if model.pluginRemovalError != nil { return "没能移除干净" }
        if model.pluginRemovalDone { return "已经移除" }
        return "移除 \(plugin?.name ?? "") 插件？"
    }

    private var message: String {
        if let error = model.pluginRemovalError { return error }
        guard let plugin else { return "" }
        if model.pluginRemovalDone {
            return """
                \(plugin.name) 已从 Claude Code 的登记表中移除，文件夹在废纸篓里，Loadout 备份里\
                也有一份拷贝。\(plugin.marketplace) 市场还在，所以在 Claude Code 里用 /plugin 可以\
                重新安装。已经在运行的会话要重启后才会卸下它。
                """
        }
        let marketplace = plugin.marketplace.isEmpty
            ? "它的市场"
            : "\(plugin.marketplace) 市场"
        return """
            这会移除 \(model.pluginContents(plugin))。文件夹会移到废纸篓，条目会从 Claude Code 的\
            插件登记表中删掉，你对它的启用或停用选择也一起清除。动手之前，所有内容会先拷贝一份到 \
            Loadout 备份。\(marketplace)不受影响，所以在 Claude Code 里用 /plugin 可以重新安装。
            """
    }
}

/// Taking a copy out of a repository, asked and answered in one place.
///
/// Two states, one dialog: the question — you are about to have two of these, and yours stops
/// following theirs — and then the receipt, with the path the copy actually landed on. The receipt
/// is the point: the copy used to happen behind a click that changed nothing on screen.
struct MakeGlobalWarningSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private var item: Item? { model.pendingMakeGlobal }
    private var done: Bool { model.makeGlobalDestination != nil || model.makeGlobalError != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                if done {
                    Image(systemName: model.makeGlobalError == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(model.makeGlobalError == nil ? Color.green : Color.orange)
                }
                Text(title)
                    .font(.title3.weight(.semibold))
            }
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let destination = model.makeGlobalDestination {
                Text(destination)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            HStack {
                Spacer()
                if done {
                    Button("完成") { close() }
                        .keyboardShortcut(.defaultAction)
                        .help("关闭")
                        .pointingHand()
                } else {
                    Button("取消") { close() }
                        .keyboardShortcut(.cancelAction)
                        .help("保持原样，只在那个仓库里生效")
                        .pointingHand()
                    Button("设为全局") { model.confirmMakeGlobal() }
                        .keyboardShortcut(.defaultAction)
                        .help("拷贝到你自己的文件夹，每个项目都能用到")
                        .pointingHand()
                }
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func close() {
        model.dismissMakeGlobal()
        dismiss()
    }

    private var title: String {
        if model.makeGlobalError != nil { return "无法拷贝" }
        if model.makeGlobalDestination != nil { return "现在它归你了" }
        return "你会有两份"
    }

    private var message: String {
        if let error = model.makeGlobalError { return error }
        guard let item else { return "" }
        let repository: String
        if case .project(let name) = item.origin { repository = "\(name) 仓库" } else { repository = "原仓库" }
        if model.makeGlobalDestination != nil {
            return "从现在起，\(item.name) 归你所有，每个项目都能用到。\(repository)保留它原来那份，两者是各自独立的文件。"
        }
        return """
            \(item.name) 会拷贝到你自己的目录，每个项目都能用到。\(repository)保留它现有的那份，\
            别人什么都不会少。但从此两者是各自独立的文件：他们的修改不会再同步到你的拷贝，你的\
            修改也不会影响他们。
            """
    }
}

struct ProjectSkillWarningSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var dontAskAgain = false

    /// The name with its own spaces, so "停用 my-skill 会" and "停用它会" both read right.
    private var disableTarget: String {
        model.pendingProjectDisable.map { " \($0.name) " } ?? "它"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("这个技能在仓库里")
                .font(.title3.weight(.semibold))
            Text("停用\(disableTarget)会把它的文件夹移到项目内的 .claude/skills-off。这个改动会和你手上的工作一起出现，一旦推送，这个仓库的所有人都会停用这个技能。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("不再提醒", isOn: $dontAskAgain)
                .toggleStyle(.checkbox)
                .help("以后停用仓库里的技能时，不再显示这条警告")
                .pointingHand()
            HStack {
                Spacer()
                Button("取消") {
                    model.pendingProjectDisable = nil
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .help("让技能保持启用")
                .pointingHand()
                Button("停用") {
                    model.confirmProjectDisable(rememberChoice: dontAskAgain)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .help("在仓库内把技能挪到一边")
                .pointingHand()
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}
