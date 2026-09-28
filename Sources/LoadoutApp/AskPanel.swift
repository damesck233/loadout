import SwiftUI
import LoadoutCore

/// The conversation, in a column beside the document.
///
/// A column rather than a sheet on purpose: the whole point of accepting a change block by block is
/// reading the proposal and the file at the same time, which a sheet over the window makes
/// impossible. Nothing here writes: accepting a block edits the draft, and Save stays Miguel's.
struct AskPanel: View {
    @Bindable var model: AppModel
    @State private var historyOpen = false
    /// The box for a model name Loadout does not know, and what is being typed into it.
    @State private var isTypingModel = false
    @State private var typedModel = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(V2.hairline)
            conversation
            // The document's own changes are decided in the document, where they can be read at
            // the width of the pane. What stays here are the files beside it, which have no editor
            // of their own — plus a line saying the document has changes waiting.
            if !sideProposals.isEmpty || documentPending > 0 {
                Divider().overlay(V2.hairline)
                proposalsArea
            }
            if model.ask.isGlobal && model.ask.hasUnsavedChanges {
                Button("保存已接受的更改") { model.saveChatChanges() }
                    .buttonStyle(V2ToolbarButtonStyle(prominent: true, enabled: !model.ask.isRunning))
                    .disabled(model.ask.isRunning)
                    .padding(10)
            }
            Divider().overlay(V2.hairline)
            composer
        }
        .background(V2.window)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 11))
                .foregroundStyle(V2.link)
            Text("对话")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(V2.text)
                .help(
                    model.ask.cli.map {
                        "\($0.label) 正在回答这段对话"
                    } ?? "在这里回答的助手"
                )
            // A bare spinner at this size is almost invisible against the bar, so it says what it
            // is doing in words beside it.
            if model.ask.isRunning {
                ProgressView().controlSize(.small).scaleEffect(0.65)
                Text("正在处理…")
                    .font(.system(size: 11))
                    .foregroundStyle(V2.link)
                    .help("\(model.ask.cli?.label ?? "助手") 还在处理。“停止”按钮在消息框旁边。")
            }
            Spacer(minLength: 6)
            Button("历史记录") { historyOpen.toggle() }
                .buttonStyle(V2ToolbarButtonStyle(prominent: false, enabled: !model.ask.history.isEmpty))
                .disabled(model.ask.history.isEmpty)
                .help("你之前的对话")
                .pointingHand(enabled: !model.ask.history.isEmpty)
                .popover(isPresented: $historyOpen, arrowEdge: .bottom) { historyList }
            Button("新对话") { model.ask.startNewConversation() }
                .buttonStyle(V2ToolbarButtonStyle(prominent: false, enabled: model.ask.canLeaveConversation))
                .disabled(!model.ask.canLeaveConversation)
                .help("开始一段新对话。当前这段会保留在“历史记录”里。")
                .pointingHand(enabled: model.ask.canLeaveConversation)
            Button("关闭") { model.showsAskPanel = false }
                .buttonStyle(V2ToolbarButtonStyle(prominent: false, enabled: true))
                .help("隐藏对话。对话会保留，下次打开时从离开的地方继续。")
                .pointingHand()
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
    }

    /// Your earlier conversations. Ids, read back from the assistant's own record —
    /// so this list can only ever offer what the assistant can still resume.
    private var historyList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("对话")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(V2.textMid)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(model.ask.history) { conversation in
                        Button {
                            model.ask.resume(conversation)
                            historyOpen = false
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(conversation.title)
                                        .font(.system(size: 12))
                                        .foregroundStyle(V2.text)
                                        .lineLimit(1)
                                    if conversation.id == model.ask.sessionID {
                                        Text("当前")
                                            .font(.system(size: 9.5))
                                            .foregroundStyle(V2.link)
                                    }
                                }
                                Text(conversation.startedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 10))
                                    .foregroundStyle(V2.textFaint)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                        }
                        .buttonStyle(.plain)
                        .background(
                            conversation.id == model.ask.sessionID ? V2.buttonHover : Color.clear
                        )
                        .pointingHand()
                    }
                }
            }
            .frame(maxHeight: 260)
        }
        .frame(width: 320)
        .padding(.bottom, 6)
    }

    // MARK: - Conversation

    private var conversation: some View {
        ScrollViewReader { scroller in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if model.ask.entries.isEmpty {
                        Text(emptyText)
                            .font(.system(size: 12))
                            .foregroundStyle(V2.textDim)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 6)
                    }
                    ForEach(model.ask.entries) { entry in
                        AskEntryRow(entry: entry).id(entry.id)
                    }
                    // While it is working and hasn't said anything yet, something has to move —
                    // otherwise a run that takes half a minute looks like a panel that broke.
                    if model.ask.isRunning {
                        AskTypingDots()
                    }
                    // An anchor to keep the newest line in view as the answer is written.
                    Color.clear.frame(height: 1).id(Self.bottomAnchor)
                }
                .padding(12)
            }
            .onChange(of: model.ask.entries.last?.text) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    scroller.scrollTo(Self.bottomAnchor, anchor: .bottom)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private static let bottomAnchor = "ask-bottom"

    private var emptyText: String {
        let name = model.ask.cli?.label ?? "助手"
        return "向 \(name) 询问你的配置。在技能上点“提问”可以把它附加到这里。保存前先检查建议的更改。"
    }

    // MARK: - Proposals

    /// Everything the assistant touched except the document on screen. That one is decided in the
    /// editor, at the width of the pane, which is the only place a long change is readable.
    private var sideProposals: [AskModel.Proposal] {
        model.ask.proposals.filter { model.ask.isGlobal || $0.id != AskModel.documentName }
    }

    private var documentPending: Int {
        model.ask.isGlobal ? 0 : (model.ask.proposals.first { $0.id == AskModel.documentName }?.pending.count ?? 0)
    }

    private var proposalsArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            if documentPending > 0 {
                Label(
                    "左侧文档中有 \(documentPending) 处更改待处理",
                    systemImage: "arrow.left"
                )
                .font(.system(size: 10.5))
                .foregroundStyle(V2.link)
            }

            if !sideProposals.isEmpty {
                Text("\(sideProposals.count) 个文件有更改")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(V2.text)

                if sideProposals.count > 1 {
                    Menu {
                        ForEach(sideProposals) { proposal in
                            Button(model.ask.proposalLabel(proposal.id)) {
                                model.ask.focusedProposalID = proposal.id
                            }
                        }
                    } label: {
                        Text(model.ask.proposalLabel(model.ask.focusedProposalID ?? sideProposals[0].id))
                            .lineLimit(1).truncationMode(.middle)
                    }
                    .menuStyle(.borderlessButton)
                }

                if let focused = sideProposals.first(where: { $0.id == model.ask.focusedProposalID })
                    ?? sideProposals.first {
                    Label(
                        focused.isNew
                            ? "\(model.ask.proposalLabel(focused.id)) 是新文件，保存时写入。"
                            : "\(model.ask.proposalLabel(focused.id)) 会在保存时写入，写入前先备份。",
                        systemImage: focused.isNew ? "doc.badge.plus" : "doc.text"
                    )
                    .font(.system(size: 10.5))
                    .foregroundStyle(V2.textDim)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(focused.blocks) { block in
                                AskBlockCard(
                                    block: block,
                                    state: state(of: block, in: focused),
                                    accept: { model.ask.accept(blockID: block.id, in: focused.id) },
                                    reject: { model.ask.reject(blockID: block.id, in: focused.id) }
                                )
                            }
                        }
                    }
                    .frame(maxHeight: 260)

                    if !focused.pending.isEmpty {
                        HStack(spacing: 6) {
                            Button("全部接受") { model.ask.acceptAll(in: focused.id) }
                                .buttonStyle(V2ToolbarButtonStyle(prominent: true, enabled: true))
                                .help("接受 \(focused.id) 中所有待处理的更改，保存时写入")
                                .pointingHand()
                            Button("全部拒绝") { model.ask.rejectAll(in: focused.id) }
                                .buttonStyle(V2ToolbarButtonStyle(prominent: false, enabled: true))
                                .help("丢弃 \(focused.id) 中所有待处理的更改，文件保持原样")
                                .pointingHand()
                        }
                    }
                }
            }
        }
        .padding(12)
    }

    private func state(of block: DiffBlock, in proposal: AskModel.Proposal) -> AskBlockCard.State {
        if proposal.accepted.contains(block.id) { return .accepted }
        if proposal.rejected.contains(block.id) { return .rejected }
        return .pending
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.ask.contexts.isEmpty {
                Text("全局 · 未附加技能")
                    .font(.system(size: 11)).foregroundStyle(V2.textDim)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(model.ask.contexts) { context in
                            Button { model.ask.detach(context.id) } label: {
                                HStack(spacing: 5) {
                                    Text(model.ask.contextLabel(context)).lineLimit(1)
                                    Image(systemName: "xmark").font(.system(size: 9))
                                }
                            }
                            .buttonStyle(V2ToolbarButtonStyle(prominent: false, enabled: !model.ask.isRunning))
                            .disabled(model.ask.isRunning)
                            .help("之后的消息不再附加 \(context.name)。之前的消息仍留在对话里。")
                            .accessibilityLabel("从对话中移除 \(context.name)")
                        }
                    }
                }
            }
            Menu {
                ForEach(model.askableCLIs) { cli in
                    Button(cli.label) { model.openChat(cli) }
                }
            } label: {
                Text(model.ask.cli?.label ?? "选择助手")
                    .font(.system(size: 11))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(!model.ask.canLeaveConversation)
            TextEditor(text: Binding(
                get: { model.ask.draftMessage },
                set: { model.ask.draftMessage = $0 }
            ))
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .frame(height: 60)
                .padding(6)
                .background(V2.well, in: RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 6) {
                modelPicker
                Text(hint)
                    .font(.system(size: 10.5))
                    .foregroundStyle(V2.textFaint)
                    .lineLimit(2)
                Spacer(minLength: 6)
                if model.ask.isRunning {
                    Button("停止") { model.ask.stop() }
                        .buttonStyle(V2ToolbarButtonStyle(prominent: false, enabled: true))
                        .help("立即结束助手的进程")
                        .pointingHand()
                } else {
                    // The shortcut is written on the button because ⌘↵ is not guessable, and
                    // Return can't be it — Return belongs to the message box, for a new line.
                    Button {
                        model.sendAskMessage()
                    } label: {
                        HStack(spacing: 6) {
                            Text("发送")
                            Text("⌘↵")
                                .font(.system(size: 11))
                                .opacity(0.6)
                        }
                    }
                        .buttonStyle(
                            V2ToolbarButtonStyle(
                                prominent: true,
                                enabled: !model.ask.draftMessage
                                    .trimmingCharacters(in: .whitespaces).isEmpty
                            )
                        )
                        .disabled(model.ask.draftMessage.trimmingCharacters(in: .whitespaces).isEmpty)
                        .keyboardShortcut(.return, modifiers: .command)
                        .help("发送这条消息（⌘↵）")
                        .pointingHand(
                            enabled: !model.ask.draftMessage
                                .trimmingCharacters(in: .whitespaces).isEmpty
                        )
                }
            }
        }
        .padding(12)
    }

    /// Which model answers, beside the message box where the decision is made.
    ///
    /// Absent entirely for an assistant Loadout cannot pass a model to, rather than shown greyed:
    /// a control that can never be used is worse than no control, because it reads as broken.
    ///
    /// "Default" is first and is what a fresh install uses — Loadout does not pick a model on
    /// anybody's behalf, it lets the CLI use whatever that person already configured. Under the
    /// written list is a box for a name Loadout has not heard of, which is what keeps the list from
    /// becoming a ceiling the day a new model ships.
    @ViewBuilder
    private var modelPicker: some View {
        if let cli = model.ask.cli, AssistantModels.acceptsAModel(assistantID: cli.id) {
            let known = AssistantModels.known(for: cli.id)
            let chosen = model.ask.chosenModel
            Menu {
                Button {
                    model.ask.chosenModel = nil
                } label: {
                    Label("默认", systemImage: chosen == nil ? "checkmark" : "")
                }
                Divider()
                ForEach(known) { entry in
                    Button {
                        model.ask.chosenModel = entry.id
                    } label: {
                        Label(
                            "\(entry.label)：\(entry.note)",
                            systemImage: chosen == entry.id ? "checkmark" : ""
                        )
                    }
                }
                Divider()
                Button("其他模型…") { isTypingModel = true }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "cpu")
                        .font(.system(size: 10))
                    Text(modelLabel(for: cli, chosen: chosen))
                        .font(.system(size: 10.5))
                }
                .foregroundStyle(chosen == nil ? V2.textFaint : V2.textMid)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("\(cli.label) 用哪个模型回答。“默认”会沿用你自己配置的模型。")
            .pointingHand()
            .popover(isPresented: $isTypingModel) {
                typedModelBox(cli: cli)
            }
        }
    }

    /// What the button reads: the friendly name when the model is one Loadout knows, the name
    /// itself when it was typed, and "Default" when nothing was chosen.
    private func modelLabel(for cli: AssistantCLI, chosen: String?) -> String {
        guard let chosen, !chosen.isEmpty else { return "默认" }
        return AssistantModels.known(for: cli.id).first { $0.id == chosen }?.label ?? chosen
    }

    private func typedModelBox(cli: AssistantCLI) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("模型名称")
                .font(.system(size: 12, weight: .semibold))
            Text("按你输入的原样传给 \(cli.label)。")
                .font(.system(size: 11))
                .foregroundStyle(V2.textFaint)
            TextField("", text: $typedModel)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
                .onSubmit { commitTypedModel() }
            HStack {
                Spacer()
                Button("取消") { isTypingModel = false }
                    .help("关闭，不更改回答所用的模型")
                    .pointingHand()
                Button("使用") { commitTypedModel() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(typedModel.trimmingCharacters(in: .whitespaces).isEmpty)
                    .help("从现在起用这个模型向 \(cli.label) 提问，直到你再次更改")
                    .pointingHand(enabled: !typedModel.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(14)
    }

    private func commitTypedModel() {
        let trimmed = typedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        model.ask.chosenModel = trimmed
        typedModel = ""
        isTypingModel = false
    }

    private var hint: String {
        guard let cli = model.ask.cli else { return "" }
        if cli.chat?.resumeTemplate == nil {
            return "\(cli.label) 每条消息都从头开始，无法接着之前的对话继续。"
        }
        return "附加的文件只有在你接受并保存后才会改变。"
    }
}

/// Three dots that rise in turn while the assistant is working.
///
/// The spinner in the header says *something* is happening; this says it is happening *here*, at the
/// bottom of the conversation, which is where the next words will appear.
private struct AskTypingDots: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(V2.textDim)
                    .frame(width: 5, height: 5)
                    .offset(y: phase == index ? -2.5 : 0)
                    .opacity(phase == index ? 1 : 0.45)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
        .task {
            // A timer rather than a repeating animation: this view comes and goes with the run, and
            // an animation left running on a removed view keeps a redraw going forever.
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(260))
                withAnimation(.easeInOut(duration: 0.22)) { phase = (phase + 1) % 3 }
            }
        }
        .accessibilityLabel("正在处理")
    }
}

/// One line of the conversation. The kinds look different on purpose: what the assistant *said* has
/// to be impossible to confuse with what it was *thinking* or what it *ran*.
private struct AskEntryRow: View {
    let entry: AskModel.Entry

    var body: some View {
        switch entry.kind {
        case .you:
            VStack(alignment: .leading, spacing: 3) {
                Text("你")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(V2.textDim)
                Text(entry.text)
                    .font(.system(size: 12))
                    .foregroundStyle(V2.text)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(V2.well, in: RoundedRectangle(cornerRadius: 8))

        case .assistant:
            Text(entry.text)
                .font(.system(size: 12.5))
                .foregroundStyle(V2.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .reasoning:
            Text(entry.text)
                .font(.system(size: 11).italic())
                .foregroundStyle(V2.textFaint)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .activity(let tool):
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: icon(for: tool))
                    .font(.system(size: 9))
                    .foregroundStyle(V2.textDim)
                    .frame(width: 12)
                Text(entry.text.isEmpty ? tool : entry.text)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(V2.textDim)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .notice:
            Text(entry.text)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(V2.textFaint)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .failure:
            Label(entry.text, systemImage: "exclamationmark.triangle")
                .font(.system(size: 11))
                .foregroundStyle(V2.amber)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func icon(for tool: String) -> String {
        switch tool {
        case "Edit", "Write", "MultiEdit", "edit", "write": return "pencil"
        case "Bash", "Shell": return "terminal"
        case "Read", "read": return "doc.text"
        default: return "wrench.and.screwdriver"
        }
    }
}

/// One change, with the old lines above the new ones and a decision to make about it.
private struct AskBlockCard: View {
    enum State { case pending, accepted, rejected }

    let block: DiffBlock
    let state: State
    let accept: () -> Void
    let reject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("第 \(block.start + 1) 行")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(V2.textDim)
                Text(block.summary)
                    .font(.system(size: 10))
                    .foregroundStyle(V2.textFaint)
                Spacer(minLength: 4)
                switch state {
                case .pending:
                    Button("拒绝", action: reject)
                        .buttonStyle(V2ToolbarButtonStyle(prominent: false, enabled: true))
                        .help("保留这几行原样，丢弃这处更改")
                        .pointingHand()
                    Button("接受", action: accept)
                        .buttonStyle(V2ToolbarButtonStyle(prominent: true, enabled: true))
                        .help("接受这处更改。保存时才会写入文件。")
                        .pointingHand()
                case .accepted:
                    Button("撤销", action: reject)
                        .buttonStyle(V2ToolbarButtonStyle(prominent: false, enabled: true))
                        .help("把这处更改再撤回来")
                        .pointingHand()
                    Label("已接受", systemImage: "checkmark")
                        .font(.system(size: 10))
                        .foregroundStyle(V2.ok)
                        .help("等你保存时写入文件")
                case .rejected:
                    Button("接受", action: accept)
                        .buttonStyle(V2ToolbarButtonStyle(prominent: false, enabled: true))
                        .help("改主意了，还是接受这处更改")
                        .pointingHand()
                    Text("已拒绝")
                        .font(.system(size: 10))
                        .foregroundStyle(V2.textFaint)
                        .help("未采用，文件保留原有的这几行")
                }
            }

            ForEach(Array(block.removedText.enumerated()), id: \.offset) { _, line in
                diffLine(line, added: false)
            }
            ForEach(Array(block.addedText.enumerated()), id: \.offset) { _, line in
                diffLine(line, added: true)
            }
        }
        .padding(8)
        .background(background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(state == .pending ? V2.hairline : Color.clear, lineWidth: 0.5)
        )
        .opacity(state == .rejected ? 0.5 : 1)
    }

    private var background: Color {
        switch state {
        case .pending: return V2.well
        case .accepted: return V2.ok.opacity(0.10)
        case .rejected: return V2.well.opacity(0.5)
        }
    }

    private func diffLine(_ line: String, added: Bool) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(added ? "+" : "−")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(added ? V2.ok : V2.issue)
            Text(line.isEmpty ? " " : line)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(added ? V2.text : V2.textMid)
                .strikethrough(!added, color: V2.textFaint)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
