import SwiftUI
import LoadoutCore

/// The reading scroller's *content* space. A position measured here is an offset down the document
/// and holds still while scrolling, which is what makes the heading offsets cheap to keep and
/// usable as scroll targets.
///
/// File scope, so the geometry closures that read these are not reaching into a main-actor type to
/// do it — and computed rather than stored, because `NamedCoordinateSpace` is not `Sendable`.
var readingContentSpace: NamedCoordinateSpace { .named("loadout.readingContent") }

/// And the reading scroller's viewport, which is what the scroll-spy's line is measured down from.
var readingViewportSpace: NamedCoordinateSpace { .named("loadout.readingViewport") }

/// The v2 detail pane: identity header with the one big switch, then cards — Token budget and
/// Details side by side, the Assistants grid, and the document with its own toolbar. Every
/// section is a rounded surface on the darker window ground, the way the design draws them.
struct DetailView: View {
    /// The narrowest the pane is allowed to be, which the sidebar gives way to keep.
    ///
    /// Not a round number by taste: the document toolbar's shortest honest arrangement needs about
    /// 390pt, and the card's 24pt margins and 10pt padding sit outside that. Under this the pane
    /// starts clipping controls instead of laying them out.
    static let minimumWidth: CGFloat = 470

    @Bindable var model: AppModel
    /// What the editor reports back — caret position and live issues — for the status bar.
    @State private var editorState = EditorState()
    /// Where the editor put each undecided change on screen, so its buttons follow it as the
    /// document scrolls.
    @State private var reviewFrames: [Int: CGRect] = [:]

    /// How tall the pane actually is right now — the editor sizes itself against this, so
    /// a taller window means a taller buffer instead of a fixed slab with dead space below.
    @State private var paneHeight: CGFloat = 900
    /// And how wide, which is what decides whether the reading rail has room to exist.
    @State private var paneWidth: CGFloat = 1200
    /// How much of the pane the identity header and the fact cards have already spent.
    ///
    /// Measured rather than assumed: the cards grow a row on the skills that have a folder
    /// beside the file, and the Assistants grid drops to two columns and then to one as the
    /// pane narrows. A constant here is what made the document ask for more height than was
    /// left, which is what put a second scroller around the whole page.
    @State private var chromeHeight: CGFloat = 380

    /// Whether the three fact cards are folded away, leaving the summary strip in their place.
    ///
    /// One answer for the whole app, and remembered: it is a preference about how somebody reads,
    /// like the reading size below, not state belonging to one skill. See DetailsDisclosure.
    @AppStorage(DetailsDisclosure.key) private var detailsCollapsed = false

    /// Whether the Details card is listing what sits beside the document. Shut by default, and
    /// deliberately not remembered between selections: opening it on one skill should not make
    /// every other skill's card taller before you have even looked at it.
    @State private var filesExpanded = false

    /// The document's headings as the renderer reports them, and which of them is being read.
    /// Both arrive as preferences, and both change rarely: the list only when the text does, the
    /// active one only when the reader crosses a heading.
    @State private var headings: [DocumentHeading] = []
    @State private var activeHeading: Int?

    /// Where each heading sits down the document, for the tick rail to scrub against, and the
    /// scroll view to put it there.
    @State private var headingOffsets: [Int: CGFloat] = [:]
    @State private var paneScroller: NSScrollView?

    /// The selected row and the cheap detail chrome must reach the screen before CoreText starts
    /// laying out the document. Keeping this separate from `selectedID` creates that paint boundary:
    /// a new selection initially gets the shell, then its Markdown enters on the next run-loop pass.
    @State private var renderedDocumentID: String?


    /// The projects the selected item was used in. Loaded when the selection or its usage
    /// changes rather than on every redraw — behind it is a query against the usage index.
    @State private var projectUsage: [ProjectUsage] = []
    /// Uses per assistant for the selected item, so the grid can show where the total came from.
    @State private var assistantUsage: [String: Int] = [:]

    // Reading preferences — the Aa popover's three choices, persisted because they are
    // preferences about reading, not state of one session.
    @AppStorage("readerFontSize") private var readerFontSize = 15.0
    @AppStorage("readerFont") private var readerFont = "system"
    @AppStorage("readerBackground") private var readerBackground = "darker"
    @State private var readerPopoverOpen = false

    private var readerDesign: Font.Design {
        switch readerFont {
        case "serif": return .serif
        case "mono": return .monospaced
        default: return .default
        }
    }

    /// The reading surface, darker than the card and the toolbar so the text reads as paper,
    /// not chrome. Ink is the extreme option, never the default. Each theme brings its own
    /// three, and in each of them the three step darker in this order.
    private var readerGround: Color { V2.reader(readerBackground) }

    var body: some View {
        if let item = model.selected {
            ScrollView {
                VStack(alignment: .leading, spacing: Self.sectionGap) {
                    chrome(item)
                    documentCard(item, rendersBody: renderedDocumentID == item.id)
                }
                .padding(.horizontal, Self.cardMargins)
                .padding(.top, Self.paneTopPadding)
                .padding(.bottom, Self.paneBottomPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(V2.window)
                .onPreferenceChange(DocumentHeadingsKey.self) { headings = $0 }
                // Lazy headings report only while they are materialized. Keep the last concrete
                // heading instead of snapping the funnel back to the first between batches.
                .onPreferenceChange(ActiveHeadingKey.self) { if let value = $0 { activeHeading = value } }
                // Accumulate exact positions as lazy headings appear. Replacing the dictionary
                // would forget every heading that just scrolled out of the materialized region.
                .onPreferenceChange(HeadingOffsetsKey.self) { headingOffsets.merge($0) { _, next in next } }
                .onChange(of: item.id) { _, _ in
                    headings = []
                    headingOffsets = [:]
                    activeHeading = nil
                    paneScroller = nil
                    renderedDocumentID = nil
                    filesExpanded = false
                }
                .onGeometryChange(for: CGSize.self, of: { $0.size }) { size in
                    paneHeight = size.height
                    paneWidth = size.width
                }
                // Re-read when the item changes, and again when a finished index pass gives
                // this one a different count than it had a moment ago. Not read at all until
                // there is a rail to read it into: it is a query, not a field on the item.
                .task(id: "\(item.id)#\(item.usage.count)#\(showsRail)") {
                    projectUsage = []
                    guard showsRail else { return }
                    let usage = await model.projectUsage(for: item)
                    guard !Task.isCancelled else { return }
                    projectUsage = usage
                }
                // The breakdown behind the total. Read whenever the total moves, so the parts
                // and the whole are never showing two different passes of the index.
                .task(id: "\(item.id)#\(item.usage.count)") {
                    assistantUsage = [:]
                    let counts = await model.usageByAssistant(for: item)
                    guard !Task.isCancelled else { return }
                    assistantUsage = counts
                }
                .task(id: item.id) {
                    // `yield()` alone may resume before AppKit's display observer. A short deadline
                    // guarantees one visible selection frame even when the run loop is busy.
                    try? await Task.sleep(for: .milliseconds(24))
                    guard !Task.isCancelled else { return }
                    renderedDocumentID = item.id
                }
        } else {
            ContentUnavailableView(
                "选择一项",
                systemImage: "square.stack.3d.up",
                description: Text("左侧列表里是 Claude 会加载的所有内容。")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(V2.window)
        }
    }

    // MARK: - Chrome above the document

    /// Everything the pane shows before the document: who this is, what it costs, and who loads
    /// it. Grouped rather than laid out loose so its height can be measured in one piece — the
    /// document below is sized from what this leaves over.
    private func chrome(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: Self.sectionGap) {
            header(item)
            if let warning = item.warning {
                warningCallout(warning)
            }
            if case .project(let repository) = item.origin, item.kind != .mcp {
                projectCallout(item, repository: repository)
            }
            if detailsCollapsed {
                DetailsSummaryStrip(summary: summary(item)) { toggleDetails() }
            } else {
                factCards(item)
            }
            // The seam belongs to this block, not to the document below it, for two reasons: it is
            // the bottom edge of the thing it folds, and being inside the measured block means the
            // document's height is worked out from a number that already includes it.
            DetailsSeam(collapsed: detailsCollapsed) { toggleDetails() }
        }
        // Safe to read back into a height the document uses: nothing in here is sized from the
        // document, so the measurement can't chase what it caused.
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
            chromeHeight = height
            // Reported outwards for the driver that photographs this pane: the check that the
            // document really rose by what the cards vacated is a subtraction of two of these, and
            // a number the view measured is the only honest source for it. See DriveScript.
            model.reportChromeHeight(height)
        }
    }

    /// Token budget, Details and Assistants — the three the fold is about.
    @ViewBuilder
    private func factCards(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: Self.sectionGap) {
            // The two fact cards share a row while the pane is wide and stack when it
            // isn't — same content either way.
            ViewThatFits(in: .horizontal) {
                // Both surfaces take the height of the taller one, rows staying at the
                // top. With four rows each they already agree; this is what keeps them
                // agreeing on the skills whose folder adds a "Files" row to Details.
                //
                // The row is already as tall as its tallest card, so each card asking for
                // the full height is the whole mechanism — no measuring, no state, and
                // nothing that could feed a height back into what produced it.
                HStack(alignment: .top, spacing: 12) {
                    if showsBudget(item) {
                        budgetCard(item).frame(maxWidth: .infinity, alignment: .top)
                    }
                    detailsCard(item).frame(maxWidth: .infinity, alignment: .top)
                }
                VStack(spacing: 12) {
                    if showsBudget(item) { budgetCard(item) }
                    detailsCard(item)
                }
            }
            if showsAssistants(item) {
                assistantsCard(item)
            }
        }
        // Folded and unfolded are the same content at two heights, so the collapse is a move rather
        // than a cross-fade: the cards slide up under the header instead of dissolving through it.
        .transition(.move(edge: .top).combined(with: .opacity))
        .clipped()
    }

    /// Who the Assistants card is for: your own skills and commands, while they are switched on.
    private func showsAssistants(_ item: Item) -> Bool {
        (item.kind == .skill || item.kind == .command)
            && item.origin == .personal && model.isEffectivelyEnabled(item)
    }

    /// The marks in the strip: the card's items, plus MCP servers — which have one owner worth
    /// naming but no card, because a server can't be linked into a second assistant.
    private func showsAssistantMarks(_ item: Item) -> Bool {
        showsAssistants(item) || item.kind == .mcp
    }

    /// The one gesture behind all three controls — the chip, the seam and ⌥⌘I — so they cannot
    /// drift into meaning three slightly different things.
    private func toggleDetails() {
        withAnimation(DetailsDisclosure.easing) { detailsCollapsed.toggle() }
    }

    /// The strip's line, built from the very strings the cards print above it.
    private func summary(_ item: Item) -> DetailsSummary {
        DetailsSummary(
            source: sourceText(item),
            usage: summaryUsage(item),
            tokens: showsBudget(item)
                ? "~\(item.budget.descriptionTokens) / ~\(Budget.estimatedTokens(characters: Budget.maxDescriptionCharacters)) tok"
                : nil,
            lines: showsBudget(item) ? "\(item.budget.bodyLines) / \(Budget.maxBodyLines) 行" : nil,
            overBudget: item.budget.isOverBudget,
            assistants: showsAssistantMarks(item)
                ? model.visibleAssistants.filter { item.assistants.contains($0.id) }
                : []
        )
    }

    /// "14 uses · 6 projects" — the Details card's sentence with the strip's own separator, and the
    /// same window named when there is nothing to count, because "no uses" alone claims more than
    /// the index knows.
    private func summaryUsage(_ item: Item) -> String {
        guard !item.usage.neverUsed else { return "\(windowSuffix)里未使用" }
        return "\(uses(item.usage.count)) ·\(count(item.usage.projectCount, of: "个项目"))"
    }

    /// The height the document card's body is given: the pane, less what the header and the
    /// cards took, less the document's own toolbar and the margins around the stack.
    ///
    /// This is what keeps the pane to one scroller. Asking for a share of the *window* — which
    /// is what a constant discount amounts to — left the page taller than the pane at every
    /// window size, so the whole thing scrolled to show a document that scrolls.
    private var documentBodyHeight: CGFloat {
        max(
            Self.minimumDocumentHeight,
            paneHeight - chromeHeight - Self.sectionGap
                - Self.paneTopPadding - Self.paneBottomPadding - Self.documentToolbarHeight
        )
    }

    /// The reading area inside that body, which sits on 12pt of padding all round.
    private var readingHeight: CGFloat { documentBodyHeight - Self.readingInset * 2 }

    /// Under this the document stops being readable, and the pane would rather scroll than
    /// shrink it further — the honest way for a window dragged shorter than its content to behave.
    static let minimumDocumentHeight: CGFloat = 260
    private static let sectionGap: CGFloat = 14
    private static let paneTopPadding: CGFloat = 20
    private static let paneBottomPadding: CGFloat = 28
    /// The toolbar's 40pt and the hairline under it.
    private static let documentToolbarHeight: CGFloat = 40.5
    private static let readingInset: CGFloat = 12
    private static let editorStatusBarHeight: CGFloat = 28

    // MARK: - Header

    private func header(_ item: Item) -> some View {
        let effectivelyEnabled = model.isEffectivelyEnabled(item)
        let parentPluginIsOff = item.pluginID != nil && model.pluginIsOff(for: item)
        return HStack(alignment: .center, spacing: 12) {
            // The theme's own gradient, the same one the app icon is drawn with — the tile is
            // the item's icon, and which kind it is comes from the glyph on it and the tab you
            // are on, not from a hue borrowed from the system palette.
            RoundedRectangle(cornerRadius: 9)
                .fill(V2.grad)
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: icon(for: item.kind))
                        .font(.system(size: 18))
                        .foregroundStyle(.white)
                }
                .shadow(color: .black.opacity(0.5), radius: 1.5, y: 1)
                .saturation(effectivelyEnabled ? 1 : 0.2)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(V2.text)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(subtitle(item))
                        .font(.system(size: 11.5))
                        .foregroundStyle(V2.textDim)
                        .lineLimit(1)
                        .help(subtitleHelp(item))
                    DetailsChip(collapsed: detailsCollapsed) { toggleDetails() }
                }
            }
            Spacer(minLength: 12)
            // Every skill has this switch now, whoever it belongs to: a plugin shipping 38 of them
            // used to mean all 38 or none.
            if item.kind != .plugin {
                if parentPluginIsOff, let id = item.pluginID {
                    Button("打开插件") {
                        model.selection = .plugins
                        model.selectedPluginID = id
                    }
                    .buttonStyle(.plain)
                    .help("打开插件，把它重新启用。你对单个技能的开关选择会保留。")
                }
                Text(effectivelyEnabled ? "已启用" : "已停用")
                    .font(.system(size: 12.5))
                    .foregroundStyle(V2.textMid)
                    .help(switchHelp(item))
                MiniSwitch(on: effectivelyEnabled, width: 40, height: 24) { model.toggle(item) }
                    .disabled(parentPluginIsOff)
                    .help(switchHelp(item))
            }
        }
    }

    /// "Personal skill · 12 KB · modified 1 month ago" — origin, weight and age in one quiet line.
    private func subtitle(_ item: Item) -> String {
        var parts = [sourceText(item)]
        if let size = fileSize(item) { parts.append(size) }
        if let modified = item.modified { parts.append("修改于 \(Usage.relative(modified))") }
        return parts.joined(separator: " · ")
    }

    /// The quiet line under the name reads as three facts run together, and only the first of them
    /// says what it is. Named here rather than guessed at: the parts it prints are conditional, so
    /// the tooltip names only the ones that are actually on screen.
    private func subtitleHelp(_ item: Item) -> String {
        var parts = ["\(this(item.kind))存放的位置"]
        if fileSize(item) != nil { parts.append("文件大小") }
        if item.modified != nil { parts.append("文件上次修改的时间") }
        guard parts.count > 1 else { return "\(this(item.kind))存放的位置" }
        return parts.dropLast().joined(separator: "、") + "和" + parts[parts.count - 1]
    }

    /// The kind as the interface names it. `briefingNoun` stays English because it is also what the
    /// assistants are told, so the screen gets its own words here.
    private func kindNoun(_ kind: ItemKind) -> String {
        switch kind {
        case .skill: return "技能"
        case .command: return "命令"
        case .agent: return "子代理"
        case .mcp: return "MCP 服务器"
        case .plugin: return "插件"
        }
    }

    /// "这个技能" / "这个 MCP 服务器": the space before a Latin noun, the way the rest of the UI spaces it.
    private func this(_ kind: ItemKind) -> String {
        let noun = kindNoun(kind)
        return noun.first?.isASCII == true ? "这个 \(noun)" : "这个\(noun)"
    }

    /// What turning the one big switch off actually does — which is never delete anything, and is
    /// worth saying, because a switch beside a file is read as one that might.
    private func switchHelp(_ item: Item) -> String {
        let noun = this(item.kind)
        if item.pluginID != nil, model.pluginIsOff(for: item) {
            return "先启用插件，才能更改\(noun)"
        }
        if item.kind == .mcp {
            return item.enabled
                ? "关闭后，这个服务器会从助手的配置里移出，原有内容会保留，随时可以放回去"
                : "打开后，这个服务器会放回助手的配置里"
        }
        return item.enabled
            ? "关闭后，所有助手都不再加载\(noun)。文件只是在磁盘上挪到一边，不会丢失"
            : "打开后，助手会重新加载\(noun)"
    }

    /// Where to send someone who wants to see this on disk: the folder for a skill, the file's
    /// folder for a command or an agent, and the JSON file itself for an MCP server.
    private func locationPath(_ item: Item) -> String? {
        if item.kind == .mcp { return item.path.map { displayPath($0) } }
        guard let folder = item.directory ?? item.path?.deletingLastPathComponent() else { return nil }
        return displayPath(folder)
    }

    private func sourceText(_ item: Item) -> String {
        // "Personal mcp" read like a typo. The kind's own noun — "MCP server" — is the word for it.
        if item.kind == .mcp {
            switch item.origin {
            case .personal: return "个人 MCP 服务器"
            // Two different things read as "MCP server in loadout": one your own config filed under
            // that project, and one the repository ships for whoever checks it out. Only the second
            // arrives with a pull, so the row says which it is.
            case .project(let name):
                return item.declaredByRepository
                    ? "\(name) 自带的 MCP 服务器" : "\(name) 中的 MCP 服务器"
            case .plugin(let name): return "来自 \(name) 插件的 MCP 服务器"
            }
        }
        let kind = kindNoun(item.kind)
        switch item.origin {
        case .personal: return "个人\(kind)"
        case .project(let name): return "\(name) 中的\(kind)"
        // "Command from codex" read as the Codex assistant, when it is a Claude Code plugin
        // called codex whose whole job is to send work to Codex.
        case .plugin(let name): return "来自 \(name) 插件的\(kind)"
        }
    }

    /// Something that lives inside a repository works only there, and the way out is one click —
    /// but only if the click can be found. As a link at the end of a row it could not: the first
    /// person to go looking for it walked past it twice. So it says what the limit is and offers
    /// the way out in the same breath, once, on the items where it is true.
    private func projectCallout(_ item: Item, repository: String) -> some View {
        // Once your copy exists there is nothing left to offer here, so the button goes and the row
        // is left saying what is true: this one belongs to the repository. Where the copy went was
        // said by the dialog that made it, path and all — leaving a live button beside a copy that
        // was already taken is how "Make global" came to be clicked twice.
        let copied = model.hasGlobalCopy(of: item)
        return HStack(spacing: 12) {
            Image(systemName: copied ? "checkmark.circle.fill" : "folder.badge.gearshape")
                .font(.system(size: 15))
                .foregroundStyle(copied ? V2.ok : V2.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(copied ? "你已经有自己的副本了" : "只在 \(repository) 里生效")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(V2.text)
                Text(
                    copied
                        ? "你的副本在所有项目里都能用。这一份属于 \(repository)，两者是各自独立的文件。"
                        : "拷贝一份给自己，就能在所有项目里使用。仓库里的那份保持不动，别人不受影响。"
                )
                .font(.system(size: 11.5))
                .foregroundStyle(V2.textMid)
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if !copied {
                Button {
                    model.makeGlobal(item)
                } label: {
                    Text("设为全局")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(V2.accent, in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .help("把 \(item.name) 拷贝到你自己的\(kindNoun(item.kind))里，仓库里的那份保持不动")
                .pointingHand()
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(V2.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
    }

    private func warningCallout(_ warning: String) -> some View {
        Label(warning, systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 12.5))
            .foregroundStyle(V2.amber)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(V2.amber.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Token budget card

    /// The budget measures a document: a description that is in context every session and a body
    /// that arrives on trigger. An MCP server has neither — it is a command line the assistant runs
    /// — so the card was four bars resting at zero against limits that do not apply to it.
    private func showsBudget(_ item: Item) -> Bool { item.kind != .mcp }

    private func budgetCard(_ item: Item) -> some View {
        V2Card {
            VStack(spacing: 0) {
                cardHeader { V2CardCaption(text: "Token 预算") }
                // All four limits the budget actually measures, in loading order: the metadata
                // that is in context in every session, then the body that only arrives on
                // trigger. Showing two of the four was why this card came up short — of height,
                // and of the truth.
                meterRow(
                    label: "描述",
                    fraction: Double(item.budget.descriptionCharacters) / Double(Budget.maxDescriptionCharacters),
                    over: item.budget.descriptionCharacters > Budget.maxDescriptionCharacters,
                    value: "~\(item.budget.descriptionTokens) / ~\(Budget.estimatedTokens(characters: Budget.maxDescriptionCharacters)) tok"
                )
                // Skills only: a command is named after its file and has no name field, so this
                // row was a bar sitting at 0 / 64 for a rule that does not apply (AC10.3).
                if item.kind == .skill {
                    meterRow(
                        label: "名称",
                        fraction: Double(item.budget.nameCharacters) / Double(Budget.maxNameCharacters),
                        over: item.budget.nameCharacters > Budget.maxNameCharacters,
                        value: "\(item.budget.nameCharacters) / \(Budget.maxNameCharacters) 字符"
                    )
                }
                meterRow(
                    label: "正文行数",
                    fraction: Double(item.budget.bodyLines) / Double(Budget.maxBodyLines),
                    over: item.budget.bodyLines > Budget.maxBodyLines,
                    value: "\(item.budget.bodyLines) / \(Budget.maxBodyLines) 行"
                )
                meterRow(
                    label: "正文词数",
                    fraction: Double(item.budget.bodyWords) / Double(Budget.maxBodyWords),
                    over: item.budget.bodyWords > Budget.maxBodyWords,
                    value: "\(item.budget.bodyWords) / \(Budget.maxBodyWords) 词"
                )
            }
            // Inside the card, so the surface is painted behind the taller frame. Outside it, the
            // container grew and the background stayed the size of the rows.
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .help(budgetHelp(item))
    }

    private func meterRow(label: String, fraction: Double, over: Bool, value: String) -> some View {
        HStack(spacing: 11) {
            Text(label)
                .font(.system(size: 12.5))
                .foregroundStyle(Color.white.opacity(0.75))
                .frame(width: 78, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.black.opacity(0.4))
                    Capsule()
                        .fill(over ? V2.amber : V2.ok)
                        .frame(width: proxy.size.width * min(1, max(0.02, fraction)))
                }
            }
            .frame(height: 5)
            Text(value)
                .font(.system(size: 11.5))
                .monospacedDigit()
                .foregroundStyle(over ? V2.amber : Color.white.opacity(0.5))
                .lineLimit(1)
        }
        .padding(.horizontal, 13)
        // The same 9 as a Details row: the two cards sit side by side, so they have to be one
        // grid rather than two that nearly agree.
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { Hairline(color: Color.white.opacity(0.06)) }
    }

    private func budgetHelp(_ item: Item) -> String {
        let base = "描述在每次会话里都占用上下文，不管用没用到。正文只在技能触发时才载入。按每 4 个字符 1 个 token 估算。"
        guard item.budget.isOverBudget else { return base }
        return (item.budget.breaches + [base]).joined(separator: "\n")
    }

    // MARK: - Details card

    private func detailsCard(_ item: Item) -> some View {
        V2Card {
            VStack(spacing: 0) {
                cardHeader { V2CardCaption(text: "详情") }
                // The way out of a repository is offered once, in the callout above, where it can
                // be seen. Twice on one screen is not twice as findable.
                detailRow(label: "来源", value: sourceText(item), help: sourceHelp(item))
                detailRow(label: "使用情况", value: usageValue(item), help: usesHelp(item))
                detailRow(label: "上次使用", value: lastUsedValue(item), help: lastUsedHelp(item))
                // An MCP server has no file of its own: it is a few lines inside `~/.claude.json`,
                // and pointing at the directory that file sits in named the home folder, which is
                // not where anybody would go looking.
                if let location = locationPath(item) {
                    detailRow(
                        label: "位置", value: location, mono: true,
                        action: ("在访达中显示", { model.revealInFinder() }),
                        actionHint: "在访达中显示 \(location)",
                        help: locationHelp(item)
                    )
                }
                // Only for something that owns a folder. On a command or an agent this listed the
                // neighbours in the same directory — other people's files, under this one's name.
                if let folder = item.directory {
                    let extras = folderContents(folder).filter { $0 != item.path?.lastPathComponent }
                    if !extras.isEmpty {
                        filesRow(extras)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    /// What is beside the document, counted when shut and spelled out when opened.
    ///
    /// It used to be one line of names run together, cut in the middle when they did not fit —
    /// which on a skill like `remotion-best-practices`, whose folder holds a dozen sibling
    /// skills, printed `remotion-int…on-multimedia/`: a name cut in half tells you nothing, and
    /// a row whose height depended on the folder pushed the document below it out of room.
    ///
    /// Shut it states the size, which is the thing you actually want at a glance. Opened, each
    /// entry is a chip in the same flow layout the filter bar uses, so names wrap onto a second
    /// line rather than being cut. Shut is the default, so the card's height no longer depends on
    /// what happens to be in the folder.
    @ViewBuilder
    private func filesRow(_ entries: [String]) -> some View {
        let folders = entries.filter { $0.hasSuffix("/") }.count
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("文件")
                .font(.system(size: 12.5))
                .foregroundStyle(Color.white.opacity(0.5))
                .frame(width: 74, alignment: .leading)
                .help("这个文件夹里除了文档之外还有什么")
            VStack(alignment: .leading, spacing: filesExpanded ? 8 : 0) {
                Button {
                    withAnimation(.easeOut(duration: 0.16)) { filesExpanded.toggle() }
                } label: {
                    HStack(spacing: 5) {
                        Text(filesSummary(entries.count, folders: folders))
                            .font(.system(size: 12.5))
                            .foregroundStyle(Color.white.opacity(0.88))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(V2.textMid)
                            .rotationEffect(.degrees(filesExpanded ? 0 : -90))
                    }
                }
                .buttonStyle(.plain)
                .help(filesExpanded ? "收起文件夹内容" : "展开文件夹内容")
                .pointingHand()

                if filesExpanded {
                    ChipFlow(spacing: 6, lineSpacing: 6) {
                        ForEach(entries, id: \.self) { entry in
                            Text(entry)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(V2.textMid)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(Color.white.opacity(0.05))
                                )
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { Hairline(color: Color.white.opacity(0.06)) }
    }

    /// "12 items · 3 folders" — the folder count only when there is one, since "0 folders" is a
    /// fact nobody asked for.
    private func filesSummary(_ total: Int, folders: Int) -> String {
        let items = count(total, of: "项")
        return folders > 0 ? "\(items) · \(count(folders, of: "个文件夹"))" : items
    }

    /// The actions whose symbol needs no word beside it. "Reveal" was here and should not have
    /// been: the row beside it is a path, but a lone folder glyph at the far edge is not something
    /// an eye finds — the same mistake this file already records about "Make global".
    private static let glyphOnlyActions: Set<String> = ["拷贝"]

    /// The glyph for a row's action. Named after what the action is, so a second action added
    /// later either finds its symbol here or falls back to something honest rather than wrong.
    private func symbol(forAction title: String) -> String {
        switch title {
        case "在访达中显示": return "folder"
        case "设为全局": return "arrow.up.right.circle"
        case "拷贝": return "doc.on.doc"
        default: return "arrow.up.forward.app"
        }
    }

    private func detailRow(
        label: String, value: String, mono: Bool = false,
        action: (String, () -> Void)? = nil, actionHint: String = "",
        help: String? = nil
    ) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 12.5))
                .foregroundStyle(Color.white.opacity(0.5))
                .frame(width: 74, alignment: .leading)
            Text(value)
                .font(mono ? .system(size: 11.5, design: .monospaced) : .system(size: 12.5))
                .foregroundStyle(mono ? V2.textMid : Color.white.opacity(0.88))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let (title, act) = action {
                // A glyph alone for the ones whose symbol is universal — a folder means reveal,
                // and the row beside it is already a path. Anything else says its verb: an action
                // nobody can name is an action nobody finds, which is exactly what happened to
                // "Make global" when it shipped as a lone arrow in a circle.
                Button(action: act) {
                    HStack(spacing: 5) {
                        Image(systemName: symbol(forAction: title))
                            .font(.system(size: 12.5))
                        if !Self.glyphOnlyActions.contains(title) {
                            Text(title)
                                .font(.system(size: 12))
                                .fitsOnOneLine()
                        }
                    }
                    .foregroundStyle(V2.link)
                }
                .buttonStyle(.plain)
                .help(actionHint.isEmpty ? title : actionHint)
                .accessibilityLabel(title)
                .pointingHand()
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { Hairline(color: Color.white.opacity(0.06)) }
        // The row's own explanation covers the label and the value; the action keeps the tooltip
        // it already had, since a button has to say what it does rather than what it shows.
        .help(help ?? "\(label)：\(value)")
    }

    /// The chosen window, for reading inside brackets and before "里未使用". The label is Chinese
    /// now and has no article to strip, so this is the label as it stands.
    private var windowSuffix: String {
        model.usageWindowLabel
    }

    private func usageValue(_ item: Item) -> String {
        // "Never used" claimed more than the numbers can: they cover the window chosen in Settings
        // › Usage, not all time. So the value says which window it looked at.
        guard !item.usage.neverUsed else { return "\(windowSuffix)里未使用" }
        return "在\(count(item.usage.projectCount, of: "个项目"))中\(uses(item.usage.count))"
    }

    /// "1 use" / "4 uses" — the phrase the Details row, the rail's Uses pair and every project
    /// row all print. One spelling, so the same number never reads two ways in one pane.
    private func uses(_ count: Int) -> String { "用过 \(count) 次" }

    private func count(_ number: Int, of noun: String) -> String {
        "\(number) \(noun)"
    }

    private func lastUsedValue(_ item: Item) -> String {
        // The window is a setting, so writing 90 days here said 90 days to somebody who had chosen
        // 30 — the row contradicting the preference that produced it.
        guard item.usage.count > 0, let last = item.usage.lastUsed else {
            return "—（\(windowSuffix)）"
        }
        return Usage.relative(last)
    }

    /// A date here is the newest activation the histories could prove, and a dash is not the same
    /// thing as never: it can also mean no history Loadout can read covers this one.
    private func lastUsedHelp(_ item: Item) -> String {
        guard item.usage.count > 0, item.usage.lastUsed != nil else {
            return "\(model.usageWindowLabel)里没有记录能证明它运行过。“设置 › 使用情况”里写明了哪些历史记录读得到，哪些格式无法作为证据。"
        }
        return "\(model.usageWindowLabel)里，助手最近一次触发\(this(item.kind))的时间"
    }

    /// Where it lives decides where it works, which is the part the words "Personal", "in a
    /// repository" and "from a plugin" leave out.
    private func sourceHelp(_ item: Item) -> String {
        let noun = this(item.kind)
        switch item.origin {
        case .personal:
            return "你自己的，放在个人文件夹里，所以每个项目都能加载\(noun)"
        case .project(let name):
            if item.declaredByRepository {
                return """
                已提交到 \(name)，检出这个仓库的人都会拿到。关闭它只会记在你自己的设置里，\
                不影响其他人
                """
            }
            return "位于 \(name) 内，只有在这个仓库里工作时才会加载"
        case .plugin(let name):
            return "随 \(name) 插件提供，更新插件时可能会替换\(noun)"
        }
    }

    /// Whose file the server is a few lines of, and what the switch does there.
    private func serverSentence(_ item: Item) -> String {
        if item.declaredByRepository {
            return "这个服务器来自仓库提交的 .mcp.json，检出这个仓库的人都会拿到。关闭它只会记在你自己的设置里，不影响其他人。"
        }
        switch Mutations.owner(of: item) {
        case "codex":
            return "这个服务器定义在 ~/.codex/config.toml 里，没有单独的文件。关闭它会设置 Codex 自己的 enabled 标记。要移除它，请在 Codex 里用 `codex mcp remove`。"
        case "antigravity":
            return "这个服务器定义在 ~/.gemini/config/mcp_config.json 里，没有单独的文件。关闭它设置的 disabled 标记和 `agy mcp disable` 设置的是同一个。"
        default:
            return "这个服务器定义在 ~/.claude.json 里，没有单独的文件。"
        }
    }

    private func locationHelp(_ item: Item) -> String {
        if item.kind == .mcp {
            return "定义这个服务器的设置文件，它只是助手其他设置中间的几行"
        }
        return item.directory == nil
            ? "文件所在的磁盘文件夹"
            : "存放\(this(item.kind))的磁盘文件夹"
    }

    private func fileSize(_ item: Item) -> String? {
        guard let path = item.path,
              let attributes = try? FileManager.default.attributesOfItem(atPath: path.path),
              let bytes = attributes[.size] as? Int
        else { return nil }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    /// Everything beside the markdown, folders marked with a trailing slash. Resolves symlinks
    /// first: several real skills are links into a shared `.agents/skills` tree, and listing
    /// a link's contents without resolving it returns nothing at all.
    private func folderContents(_ folder: URL) -> [String] {
        let fm = FileManager.default
        let target = folder.resolvingSymlinksInPath()
        guard let entries = try? fm.contentsOfDirectory(
            at: target, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries
            .map { url -> String in
                var isDirectory: ObjCBool = false
                _ = fm.fileExists(atPath: url.path, isDirectory: &isDirectory)
                return url.lastPathComponent + (isDirectory.boolValue ? "/" : "")
            }
            .sorted()
    }

    private func displayPath(_ url: URL) -> String {
        url.path.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"
        )
    }

    // MARK: - Assistants card

    private func assistantsCard(_ item: Item) -> some View {
        let assistants = model.visibleAssistants
        let loaded = assistants.filter { item.assistants.contains($0.id) }.count
        return V2Card {
            VStack(spacing: 0) {
                cardHeader {
                    HStack(spacing: 8) {
                        V2CardCaption(text: "助手")
                        Text("已加载 \(loaded) / \(assistants.count)")
                            .font(.system(size: 11))
                            .foregroundStyle(V2.textFaint)
                            .help("下方助手中有几个装了这个技能。总数是 Loadout 在这台 Mac 上找到、并且在设置里保持显示的助手")
                    }
                }
                // Four up is the design's shape, but only while a cell has room for a name and a
                // verb beside it. Below that it drops to two and then to one, because a squeezed
                // four-up turns "loaded" into three stacked letters.
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: 0), count: assistantColumns
                    ),
                    spacing: 0
                ) {
                    ForEach(assistants) { assistant in
                        assistantCell(assistant, item: item)
                    }
                }
            }
        }
    }

    /// One cell needs about 200pt before the label starts truncating into initials.
    private var assistantColumns: Int {
        if cardWidth >= 800 { return 4 }
        if cardWidth >= 400 { return 2 }
        return 1
    }

    /// How wide a card actually is: the pane, less the margins the stack holds them in. Every
    /// decision about what fits on a card is about this number, not about the pane's own width.
    private var cardWidth: CGFloat { paneWidth - Self.cardMargins * 2 }
    private static let cardMargins: CGFloat = 24

    @ViewBuilder
    private func assistantCell(_ assistant: Assistant, item: Item) -> some View {
        let has = item.assistants.contains(assistant.id)
        let none = !has && !assistant.hasSkillsFolder
        // The one assistant that holds the last copy: unlinking there would take the skill with
        // it, so the row never becomes a click. `Mutations.unshare` refuses the same thing, but
        // refusing after the click means the app offered something it could not do. Read off the
        // live item, so the moment a second assistant loads the skill this row is a button again.
        let onlyCopy = has && item.assistants.count == 1

        if onlyCopy {
            // Still reads as loaded — the check is true and worth seeing. Only the removal is
            // gone, dimmed the way a disabled control is.
            assistantRow(assistant, has: has, none: none)
                .help("这是唯一的副本，移除会删掉这个技能。请改为停用。")
                .opacity(0.55)
                .spotlight(Spotlight.assistant(assistant.id))
        } else {
            Button {
                model.setAssistant(assistant, on: item, present: !has)
            } label: {
                assistantRow(assistant, has: has, none: none)
                    // On the content, not on the Button around it. A plain-styled button hands its
                    // tracking area to the label, and a tooltip hung outside that never fires —
                    // which is why no cell in this grid had one, whatever it showed.
                    .help(assistantHelp(assistant, has: has))
            }
            .buttonStyle(.plain)
            .pointingHand()
            .spotlight(Spotlight.assistant(assistant.id))
        }
    }

    private func assistantRow(_ assistant: Assistant, has: Bool, none: Bool) -> some View {
        HStack(spacing: 9) {
            AssistantMark(assistant: assistant, present: has || !none, size: 20)
            Text(assistant.label)
                .font(.system(size: 12.5))
                .foregroundStyle(Color.white.opacity(none ? 0.4 : 0.88))
                .lineLimit(1)
                .fixedSize()
            // Beside the name, not out in the state column: it belongs to this assistant,
            // and against the column it read as part of the word next to it.
            if let count = assistantUsage[assistant.id], count > 0 {
                Text("\(count)")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(V2.textFaint)
                    .fitsOnOneLine()
            }
            Spacer(minLength: 6)
            // One glyph per state, all the same size and shape, so the column reads as a
            // column. Colour still carries the meaning at a distance — the healthy hue for
            // carried, the link hue for available, grey for nothing to carry it with — and
            // the words move to the tooltip, where the space is free. It also stops "loaded"
            // from stacking into three letters when the grid squeezes to four up.
            Image(systemName: has ? "checkmark.circle.fill" : (none ? "minus.circle" : "plus.circle"))
                .font(.system(size: 13))
                .foregroundStyle(has ? V2.ok : (none ? V2.muted : V2.link))
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { Hairline(color: Color.white.opacity(0.06)) }
        .overlay(alignment: .trailing) { Hairline(color: Color.white.opacity(0.06), vertical: true) }
        .contentShape(Rectangle())
    }

    private func assistantHelp(_ assistant: Assistant, has: Bool) -> String {
        let count = assistantUsage[assistant.id] ?? 0
        let fired = count > 0
            ? "\(assistant.label) 在\(model.usageWindowLabel)里触发过它 \(count) 次。"
            : ""
        if has {
            // The glyph says carried; the tooltip is where "loaded" now lives in words.
            return "已在 \(assistant.label) 中加载。" + fired
                + "点按可让 \(assistant.label) 不再加载这个技能。"
        }
        if assistant.hasSkillsFolder {
            // The one that reads as a contradiction until it is spelled out: used, not loaded.
            let past = count > 0 ? "它现在没有在那里加载。" : ""
            return fired + past + "点按可把这个技能添加到 \(assistant.label)。"
        }
        return "\(assistant.label) 还没有技能文件夹。点按会创建 \(assistant.skillsRoot.path) 并添加这个技能。"
    }

    // MARK: - Document card

    /// Whether the bar above the document has anything in it. On a server the repository ships,
    /// everything it can hold is gone — no Preview/Edit, no reader, no Ask, no budget chip, no
    /// Remove — and drawing it anyway left an empty band with a hairline under it.
    private func showsDocumentToolbar(_ item: Item) -> Bool {
        item.kind != .mcp || model.canRemove(item)
    }

    private func documentCard(_ item: Item, rendersBody: Bool) -> some View {
        V2Card {
            VStack(spacing: 0) {
                if showsDocumentToolbar(item) {
                    documentToolbar(item)
                    Hairline(color: Color.white.opacity(0.08))
                }
                if rendersBody {
                    documentBody(item)
                } else {
                    // Same footprint as the reader, so admitting the document never moves the
                    // cards above it or causes a second window-level layout jump.
                    Color.clear.frame(height: documentBodyHeight)
                }
            }
        }
    }

    /// The bar gives up the budget chip first — the same two numbers sit in the Token budget card
    /// a few points above — and then the ⌘S hint on Save. What it never gives up is a control:
    /// truncating "Revert" to "R" is worse than not showing a duplicate line count.
    private func documentToolbar(_ item: Item) -> some View {
        ViewThatFits(in: .horizontal) {
            toolbarRow(item, chip: true, shortcut: true)
            toolbarRow(item, chip: false, shortcut: true)
            toolbarRow(item, chip: false, shortcut: false)
        }
    }

    private func toolbarRow(_ item: Item, chip: Bool, shortcut: Bool) -> some View {
        HStack(spacing: 8) {
            // Reading or editing: one segmented switch, because they are the same document
            // in two modes. A server has no document and nothing to edit, so it gets neither
            // segment — offering Edit there was a control that could only disappoint.
            if item.kind != .mcp {
                HStack(spacing: 1) {
                    viewModeTab("预览", selected: model.showsPreview) { model.showsPreview = true }
                    // The dot is the unsaved marker the design asks for on the Edit segment
                    // itself, so the state is visible even while reading the preview.
                    viewModeTab(model.isDirty ? "编辑 •" : "编辑", selected: !model.showsPreview) {
                        model.showsPreview = false
                    }
                }
                .padding(2)
                .background(V2.well, in: RoundedRectangle(cornerRadius: 7))
            }

            // Reading before asking: Aa belongs with the Preview/Edit switch it modifies.
            if model.showsPreview, item.kind != .mcp {
                readerButton
            }

            if item.isEditable {
                askButton
            }

            Spacer(minLength: 8)

            // Same reason the card above is gone on a server: there is no body to count lines of.
            if chip, showsBudget(item) {
                budgetChip(item)
            }

            // The one destructive thing a server has. It is here rather than only in the row's
            // context menu because a menu nobody opens is not where a person looks for it.
            if model.canRemove(item) {
                Button("移除") { model.isConfirmingDelete = true }
                    .buttonStyle(V2ToolbarButtonStyle(prominent: false, enabled: true))
                    .help("把这个服务器从助手的设置里拿掉。它没有废纸篓可去，所以 Loadout 会先把文件拷贝到备份里")
                    .pointingHand()
            }

            if item.isEditable {
                Button("复原") { model.revert() }
                    .buttonStyle(V2ToolbarButtonStyle(prominent: false, enabled: model.isDirty))
                    .disabled(!model.isDirty)
                    .help("丢弃未保存的更改，从磁盘重新载入文件")
                    .pointingHand(enabled: model.isDirty)
                Button {
                    model.save()
                } label: {
                    HStack(spacing: 6) {
                        Text("保存")
                        if shortcut {
                            Text("⌘S")
                                .font(.system(size: 11))
                                .opacity(0.6)
                        }
                    }
                }
                .buttonStyle(V2ToolbarButtonStyle(prominent: true, enabled: model.isDirty))
                .disabled(!model.isDirty)
                .keyboardShortcut("s", modifiers: .command)
                .help("把你的更改写入磁盘上的文件（⌘S）")
                .pointingHand(enabled: model.isDirty)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
    }

    private func viewModeTab(_ name: String, selected: Bool, action: @escaping () -> Void) -> some View {
        V2SegmentTab(label: name, selected: selected, action: action)
            .help(name.hasPrefix("预览") ? "以渲染后的 Markdown 阅读文档" : "编辑原始文件")
    }

    /// The body's line count against the documented limit, always in view while editing —
    /// in the healthy hue while inside, amber the moment the file crosses the line.
    private func budgetChip(_ item: Item) -> some View {
        let over = item.budget.bodyLines > Budget.maxBodyLines
        let color = over ? V2.amber : V2.ok
        return HStack(spacing: 5) {
            Image(systemName: "clock")
                .font(.system(size: 10))
            Text("\(item.budget.bodyLines) / \(Budget.maxBodyLines) 行")
                .monospacedDigit()
        }
        .font(.system(size: 11.5))
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .frame(height: 22)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(color.opacity(0.28), lineWidth: 0.5))
        .help(budgetHelp(item))
    }

    /// Safari Reader's pattern: one quiet Aa button, and the three reading choices live in
    /// its popover — never as loose sliders on the bar.
    private var readerButton: some View {
        Button("Aa") { readerPopoverOpen.toggle() }
            .buttonStyle(V2ToolbarButtonStyle(prominent: false, enabled: true))
            .help("阅读字号、字体和背景")
            .pointingHand()
            .popover(isPresented: $readerPopoverOpen, arrowEdge: .bottom) {
                readerPopover
            }
            .onAppear {
                // The screenshot hook again — presented after the window settles, since a
                // popover asked for before its anchor has laid out never shows at all.
                if ProcessInfo.processInfo.environment["LOADOUT_OPEN"] == "reader" {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { readerPopoverOpen = true }
                }
            }
    }

    private var readerPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button("A") { readerFontSize = max(13, readerFontSize - 1) }
                    .font(.system(size: 11))
                    .buttonStyle(V2ToolbarButtonStyle(prominent: false, enabled: readerFontSize > 13))
                    .pointingHand(enabled: readerFontSize > 13)
                Slider(value: $readerFontSize, in: 13...20, step: 0.5)
                    .controlSize(.small)
                    .tint(V2.accent)
                    .pointingHand()
                Button("A") { readerFontSize = min(20, readerFontSize + 1) }
                    .font(.system(size: 15))
                    .buttonStyle(V2ToolbarButtonStyle(prominent: false, enabled: readerFontSize < 20))
                    .pointingHand(enabled: readerFontSize < 20)
                Text("\(readerFontSize, specifier: "%.0f") pt")
                    .font(.system(size: 11.5))
                    .monospacedDigit()
                    .foregroundStyle(V2.textDim)
                    .frame(width: 36, alignment: .trailing)
            }
            readerSegments(
                options: [("system", "系统"), ("serif", "衬线"), ("mono", "等宽")],
                selection: $readerFont,
                help: "阅读文档所用的字体"
            )
            readerSegments(
                options: [("dark", "暗"), ("darker", "更暗"), ("ink", "墨黑")],
                selection: $readerBackground,
                help: "文字背后纸面的深浅，“墨黑”最深"
            )
        }
        .padding(12)
        .frame(width: 280)
        .background(V2.popover)
    }

    private func readerSegments(
        options: [(String, String)], selection: Binding<String>, help: String
    ) -> some View {
        HStack(spacing: 1) {
            ForEach(options, id: \.0) { value, label in
                V2SegmentTab(label: label, selected: selection.wrappedValue == value) {
                    selection.wrappedValue = value
                }
                .frame(maxWidth: .infinity)
                // On each segment rather than the row: "Ink" and "Darker" name a shade nobody can
                // rank on sight, and the row's own tooltip never reaches the segments' hit areas.
                .help(help)
            }
        }
        .padding(2)
        .background(V2.well, in: RoundedRectangle(cornerRadius: 7))
    }

    /// One button when exactly one assistant CLI is installed, a menu when there's a choice,
    /// and a disabled button naming what it's looking for when there's none.
    @ViewBuilder
    private var askButton: some View {
        // Only the assistants Loadout can actually hold a conversation with. Offering one it
        // can't would be a menu entry that opens a window and then apologises.
        let clis = model.askableCLIs
        if clis.isEmpty {
            Button {} label: { askLabel }
                .buttonStyle(V2ToolbarButtonStyle(prominent: false, enabled: false))
                .disabled(true)
                .help("会在 PATH 里查找 \(AssistantCLIRegistry.chatCapableLabels.joined(separator: " 或 "))，但都没有安装。")
        } else if let only = clis.count == 1 ? clis.first : nil {
            Button { model.askAssistant(only) } label: { askLabel }
                .buttonStyle(V2ToolbarButtonStyle(prominent: false, enabled: true))
                .help(askHelp(only))
                .pointingHand()
        } else {
            Menu {
                ForEach(clis) { cli in
                    Button(cli.label) { model.askAssistant(cli) }
                }
            } label: {
                askLabel
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            // Inside the pill's padding on purpose: a borderless menu hit-tests only its own label,
            // so the 10pt of pill either side is decoration, and the hand must not claim otherwise.
            .pointingHand()
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(V2.button, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
            .help("就这个技能向助手提问。在你接受更改并保存之前，不会写入任何内容。")
            .pointingHand()
        }
    }

    /// The button says which of the two things it does, because they are not the same promise: a
    /// conversation can change the file once you accept a change, and the one-shot sheet cannot.
    private func askHelp(_ cli: AssistantCLI) -> String {
        AskModel.canChat(cli)
            ? "在文档旁边和 \(cli.label) 聊聊这个技能。它在文件夹的副本里工作，只有你接受更改并保存后，你的文件才会变。"
            : "就这个技能向 \(cli.label) 问一个问题。它只用文字回答，不写入任何内容。"
    }

    private var askLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 11))
                .foregroundStyle(V2.link)
            Text("提问")
                .font(.system(size: 12))
        }
    }

    // MARK: Document body

    @ViewBuilder
    private func documentBody(_ item: Item) -> some View {
        if item.kind == .mcp {
            // One of these is in a file of its own and the other is not, so the sentence cannot be
            // the same. Saying "~/.claude.json" over a server that came out of a repository's
            // `.mcp.json` pointed at the wrong file and read as the app not knowing where it was.
            Text(serverSentence(item))
                .font(.system(size: 12.5))
                .foregroundStyle(V2.textMid)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if model.showsPreview {
            readingArea(item)
        } else if item.isEditable {
            VStack(spacing: 0) {
                if model.reviewLayout != nil {
                    reviewBanner
                }
                ZStack(alignment: .topTrailing) {
                    MarkdownEditor(
                        text: $model.draft,
                        original: model.diskDraft,
                        review: model.reviewLayout,
                        onReviewFrames: { reviewFrames = $0 },
                        onEdit: { model.isDirty = true },
                        onState: { editorState = $0 }
                    )
                    // Each undecided change gets its pair of buttons at its own height, so the
                    // decision is taken where the change is rather than in a list somewhere else.
                    ForEach(reviewFrames.sorted(by: { $0.value.minY < $1.value.minY }), id: \.key) { block, rect in
                        reviewControls(block: block)
                            .offset(y: max(2, rect.minY + 2))
                            .padding(.trailing, 14)
                    }
                }
                // As tall as the pane has left — the buffer scrolls inside the editor, and the
                // status bar under it comes out of the same allowance rather than off the end.
                .frame(height: max(120, documentBodyHeight - Self.editorStatusBarHeight))
                .clipped()
                editorStatusBar(item)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label("这来自插件，所以是只读的。", systemImage: "lock")
                    .font(.system(size: 11))
                    .foregroundStyle(V2.textDim)
                ScrollView {
                    Text(model.draft)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 300)
            }
            .padding(16)
        }
    }

    // MARK: Reviewing the assistant's changes

    /// Says what the buffer is, because it is not the file: it holds both sides of every undecided
    /// change, and typing is off until they are decided.
    private var reviewBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 10))
                .foregroundStyle(V2.link)
            Text(model.ask.pendingCount == 1
                 ? "有 1 处建议的更改，接受或拒绝后才能继续编辑"
                 : "有 \(model.ask.pendingCount) 处建议的更改，全部处理后才能继续编辑")
                .font(.system(size: 11))
                .foregroundStyle(V2.text)
            Spacer(minLength: 6)
            Button("全部接受") { model.acceptAllReviewChanges() }
                .buttonStyle(V2ToolbarButtonStyle(prominent: true, enabled: true))
                .help("把所有建议的更改写进文档（之后仍需保存）")
                .pointingHand()
            Button("全部拒绝") { model.rejectAllReviewChanges() }
                .buttonStyle(V2ToolbarButtonStyle(prominent: false, enabled: true))
                .help("丢弃所有建议的更改，文件保持原样")
                .pointingHand()
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(V2.link.opacity(0.10))
        .overlay(alignment: .bottom) { Rectangle().fill(V2.hairline).frame(height: 0.5) }
    }

    private func reviewControls(block: Int) -> some View {
        HStack(spacing: 4) {
            Button("拒绝") { model.rejectReviewChange(block) }
                .buttonStyle(V2ToolbarButtonStyle(prominent: false, enabled: true))
                .help("这一处保持原样")
                .pointingHand()
            Button("接受") { model.acceptReviewChange(block) }
                .buttonStyle(V2ToolbarButtonStyle(prominent: true, enabled: true))
                .help("把这处更改写进文档（之后仍需保存）")
                .pointingHand()
        }
        .padding(3)
        .background(V2.popover, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(V2.hairline, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
    }

    // MARK: Reading area and rail

    /// Text plus rail. The reading measure belongs to reading, not to the window, so a wide
    /// pane can't be spent on longer lines — but it needn't be spent on nothing either: the
    /// width the text refuses goes to a rail holding what you would otherwise have to scroll
    /// away from. Under the breakpoint there is no room for both and the text stands alone.
    private func readingArea(_ item: Item) -> some View {
        ScrollViewReader { proxy in
            HStack(alignment: .top, spacing: 0) {
                // Both rails sit outside the scroller, so they hold still while the document moves —
                // no sticky offsets, no measuring, nothing chasing a viewport.
                tickRail { heading in
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(
                            heading.id == headings.first?.id
                                ? DocumentAnchor.frontmatter
                                : DocumentAnchor.heading(heading.id),
                            anchor: .top
                        )
                    }
                }
                    .frame(width: Self.tickRailGutter, alignment: .leading)
                    // Above the page, not behind it. The rail is the earlier sibling, so without this
                    // the card it opens — which reaches into the page by design — was drawn under the
                    // page's own ground and never seen.
                    .zIndex(1)
                page(item)
            }
        }
        // As tall as the pane has left and no taller, the way the editor already is: the document
        // scrolls inside the card instead of taking the header and the fact cards up with it.
        .frame(height: readingHeight)
        .padding(Self.readingInset)
    }

    /// The width the reading area has to lay out in: the card, less its own inset and the strip
    /// the ticks are pinned to.
    private var readingWidth: CGFloat {
        cardWidth - Self.readingInset * 2 - Self.tickRailGutter
    }

    private func page(_ item: Item) -> some View {
        HStack(alignment: .top, spacing: showsRail ? Self.railGap : 0) {
            ScrollView {
                MarkdownView(
                    text: model.draft, fontSize: readerFontSize, design: readerDesign,
                    proseWidth: column
                )
                    .frame(maxWidth: column, alignment: .leading)
                    .padding(.vertical, 18)
                    // On the content: a heading's offset in here is its offset down the document,
                    // and holds still while scrolling.
                    .coordinateSpace(readingContentSpace)
                    .background(PaneScroller { paneScroller = $0 })
            }
            .coordinateSpace(readingViewportSpace)
            // No second bar down the middle of the window. The page keeps the one scroller the eye
            // expects, and what says where you are inside the document is the tick rail — which is
            // the whole reason it grew a funnel.
            .scrollIndicators(.hidden)
            .frame(maxWidth: column)
            .id(item.id)
            if showsRail {
                // The rail gets a scroller of its own rather than a height it may exceed. Its
                // outline and its project list both grow with the document, and a column that
                // asks for more than the card has does not push anything aside — SwiftUI centres
                // it in the frame it was given and lets it draw outside, over the toolbar above
                // and past the card below. Scrolling is what turns the height into a fact.
                ScrollView {
                    readingRail(item)
                }
                .scrollIndicators(.hidden)
                .frame(width: Self.railWidth)
                .padding(.vertical, 18)
            }
        }
        // The sheet takes the whole card, and it is the document that fills it — the rail and the
        // margins keep the widths the design drew them at, and everything past those goes to the
        // text. It used to be the other way round: the text held a fixed measure and the leftover
        // width was spent on nothing, which is what left a sheet of paper floating in a band of
        // window on either side.
        .padding(.horizontal, Self.readingPadding)
        .background(readerGround, in: RoundedRectangle(cornerRadius: 10))
        // Fills what is left after the ticks' strip, so the ticks stay pinned to the leading edge
        // at every width instead of travelling inwards with the page.
        .frame(maxWidth: .infinity)
    }

    /// How wide the document itself is drawn: everything the reading area has, less the rail and
    /// the sheet's margins.
    ///
    /// No cap. The 84-character measure is still the *floor* — it is what the rail has to leave
    /// standing to be allowed to exist at all — but above that the width belongs to the document,
    /// because the alternative is what this replaced: a fixed column and a band of empty sheet
    /// beside it. Never below a readable minimum, so a pane dragged narrow crushes nothing.
    private var column: CGFloat {
        let rail = showsRail ? Self.railGap + Self.railWidth : 0
        return max(Self.narrowestColumn, readingWidth - Self.readingPadding * 2 - rail)
    }

    /// Under this the document is no longer a document, and the pane would rather clip than keep
    /// shrinking it — the same bargain `minimumWidth` makes for the pane as a whole.
    private static let narrowestColumn: CGFloat = 260

    /// The ticks, at the top of the reading area rather than centred in it: the first mark starts
    /// level with the top of the sheet beside it, and the column reads as a ruler down the page
    /// instead of a thing floating in the middle of it.
    private func tickRail(onJump: @escaping (DocumentHeading) -> Void) -> some View {
        TickRail(
            headings: headings,
            active: activeIndex,
            // What the strip may actually occupy: the reading area, less the inset it starts on.
            // The ticks size themselves from this, so it has to be the room they really have.
            available: readingHeight - Self.railTopInset,
            offsets: headingOffsets,
            pageTop: 0,
            onJump: onJump,
            onScrub: { offset in paneScroller?.scrollDocument(to: offset) },
            estimatedOffset: { heading in
                heading.progress * (paneScroller?.documentView?.bounds.height ?? 0)
            }
        )
        .padding(.top, Self.railTopInset)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// The inset the ticks start on: none.
    ///
    /// They used to start on the same 18pt the text is inset by, on the theory that the first mark
    /// should be level with the document's first line. It isn't what the eye judges — beside a
    /// sheet of paper, the column of marks is read against the *top of the sheet*, and 18 points of
    /// nothing above the first mark reads as the ruler having slipped down.
    private static let railTopInset: CGFloat = 0

    /// The active heading as a position in the outline rather than its id, which is what the ticks
    /// count in — the frontmatter's mark is not a heading and has no heading number.
    private var activeIndex: Int {
        guard let activeHeading,
              let index = headings.firstIndex(where: { $0.id == activeHeading })
        else { return 0 }
        return index
    }

    /// The rail is Fluida's whole point, and even there it has to earn its place: the prose
    /// measure, the gutter, the rail and the reading surface's own padding all have to fit inside
    /// the card before the rail is allowed to exist.
    ///
    /// The 84-character measure is what it is tested against, and it is the only place that number
    /// still decides anything: above the threshold the document takes whatever width there is, but
    /// the rail may never be what pushes the text below a comfortable line. Derived from the
    /// reading size rather than fixed, so it tracks the Aa panel's larger sizes — at the default
    /// 15pt it works out at 1172pt of pane, within eight points of the 1180 the design asked for.
    private var showsRail: Bool {
        cardWidth >= proseColumn + Self.railGap + Self.railWidth + Self.readingPadding * 2
    }

    private var proseColumn: CGFloat {
        MarkdownView.width(fontSize: readerFontSize, characters: MarkdownView.proseCharacters)
    }
    private static let railWidth: CGFloat = 264
    private static let railGap: CGFloat = 64
    /// The sheet's own margin, left and right of everything on it.
    ///
    /// Wider than it was: at 20 the text sat almost against the edge of the paper, which reads as
    /// a document that overflowed rather than one that was placed. It comes out of the text's
    /// width, which is now the width that has room to give.
    private static let readingPadding: CGFloat = 32
    private static let tickRailGutter: CGFloat = 52

    private func readingRail(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if !headings.isEmpty {
                railOnThisPage
                railRule
            }
            railMetadata(item)
            railRule
            railUsedIn(item)
            Spacer(minLength: 0)
        }
        .frame(width: Self.railWidth, alignment: .leading)
    }

    /// Where a section starts, for either rail to jump to. The first entry goes to the very top:
    /// above it is the frontmatter's own margin, and stopping short of that reads as a failed jump.
    private func destination(of heading: DocumentHeading) -> CGFloat {
        guard heading.id != headings.first?.id else { return 0 }
        return max(0, (headingOffsets[heading.id] ?? 0) - Self.readingTopInset)
    }

    static let readingTopInset: CGFloat = 24

    private var railRule: some View {
        Hairline(color: V2.hairlineSoft).padding(.vertical, 9)
    }

    // MARK: On this page

    private var railOnThisPage: some View {
        VStack(alignment: .leading, spacing: 7) {
            V2CardCaption(text: "本页内容", size: 10.5, weight: .medium, color: V2.textFaint)
            ForEach(headings) { heading in
                railHeadingRow(heading)
            }
        }
    }

    private func railHeadingRow(_ heading: DocumentHeading) -> some View {
        // Before the reader has passed anything, the first entry stands for where they are.
        let active = heading.id == (activeHeading ?? headings.first?.id)
        return Button {
            // The same destination the ticks use, so the two readings of the outline can't disagree
            // about where a section starts.
            paneScroller?.scrollDocument(to: destination(of: heading), animated: true)
        } label: {
            Text(heading.title)
                .font(.system(size: 11.5))
                .foregroundStyle(Color.white.opacity(active ? 0.92 : 0.42))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Every row carries the indent, active or not, so arriving at a section
                // lights its marker instead of nudging the text sideways.
                .padding(.leading, 9 + CGFloat(heading.level - 1) * 8)
                .padding(.vertical, 1)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(V2.accent)
                        .frame(width: 2)
                        .opacity(active ? 1 : 0)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(heading.title)
        .pointingHand()
    }

    // MARK: Metadata pairs

    private func railMetadata(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            railPair(
                "修改时间", item.modified.map { Usage.relative($0) } ?? "—",
                help: "磁盘上的文件上次修改的时间"
            )
            railPair(
                "使用", item.usage.neverUsed ? "\(windowSuffix)里未使用" : uses(item.usage.count),
                help: usesHelp(item)
            )
            railPair("来源", sourceText(item), help: sourceHelp(item))
        }
    }

    /// What the number actually counts. It used to read Claude Code alone; now that it adds up
    /// several assistants over a window the person chose, "1 use" on its own is a riddle.
    private func usesHelp(_ item: Item) -> String {
        let assistants = model.countedAssistantLabels
        let counted = assistants.count > 1
            ? assistants.dropLast().joined(separator: "、") + " 和 " + assistants[assistants.count - 1]
            : assistants.joined()
        let scope = "统计的是\(model.usageWindowLabel)里 \(counted) 有据可查的触发次数。"

        guard !item.usage.neverUsed else {
            return scope + "这一项没有记录。可以在“设置 › 使用情况”里查看哪些历史记录读得到。"
        }
        let ordered = assistantUsage.sorted { left, right in
            left.value == right.value ? left.key < right.key : left.value > right.value
        }
        let breakdown = ordered.map { entry -> String in
            let label = model.assistants.first { $0.id == entry.key }?.label ?? entry.key
            return "\(label)：\(entry.value)"
        }.joined(separator: "，")
        let where_ = breakdown.isEmpty ? "" : "（\(breakdown)）"
        return "在 \(count(item.usage.projectCount, of: "个项目"))中\(uses(item.usage.count))\(where_)。\(scope)"
    }

    private func railPair(_ label: String, _ value: String, help: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(Color.white.opacity(0.35))
                .frame(width: 62, alignment: .leading)
            Text(value)
                .font(.system(size: 11.5))
                .foregroundStyle(Color.white.opacity(0.7))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .help(help ?? "\(label)：\(value)")
    }

    // MARK: Used in

    private func railUsedIn(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            V2CardCaption(text: "用过它的项目", size: 10.5, weight: .medium, color: V2.textFaint)
                .help("\(model.usageWindowLabel)里触发过它的项目，按次数从多到少排列")
            if projectUsage.isEmpty {
                Text("没有使用记录")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.white.opacity(0.35))
                    .help("\(model.usageWindowLabel)里没有哪个项目记录到它运行过。“设置 › 使用情况”里写明了哪些历史记录读得到，哪些格式无法作为证据。")
            } else {
                ForEach(projectUsage) { usage in
                    railProjectRow(usage)
                }
                // The Details card in this same pane says "in N projects", so a silently
                // truncated list reads as a contradiction rather than as a top eight.
                if item.usage.projectCount > projectUsage.count {
                    Text("还有 \(item.usage.projectCount - projectUsage.count) 个")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.white.opacity(0.35))
                        .padding(.leading, 19)
                        .help("列表只显示用得最多的 8 个项目")
                }
            }
        }
    }

    private func railProjectRow(_ usage: ProjectUsage) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "folder")
                .font(.system(size: 12))
                .foregroundStyle(V2.textFaint)
            Text(usage.project)
                .font(.system(size: 11.5))
                .foregroundStyle(Color.white.opacity(0.7))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(usage.count)")
                .font(.system(size: 11.5))
                .monospacedDigit()
                .foregroundStyle(V2.textFaint)
        }
        .help("\(model.usageWindowLabel)里，在 \(usage.project) 中\(uses(usage.count))")
    }

    /// The design's editor footer: where the caret is, how big the buffer is, whether it is
    /// saved, what it costs in tokens, and how many live issues the validator sees.
    private func editorStatusBar(_ item: Item) -> some View {
        let liveBudget = Budget.measure(document: model.draft)
        return HStack(spacing: 14) {
            Text("第 \(editorState.line) 行，第 \(editorState.column) 列")
                .help("光标位置：先行后列")
            Text("\(model.draft.components(separatedBy: "\n").count) 行")
                .help("整个文件的行数，包括 Frontmatter。预算只算正文，所以那边的数字会小一些。")
            Text("Markdown")
            Text("UTF-8")
            Spacer()
            if !editorState.issues.isEmpty {
                Text("\(editorState.issues.count) 个问题")
                    .foregroundStyle(V2.issue)
                    .help(editorState.issues.map(\.message).joined(separator: "\n"))
            }
            Text("描述 ~\(liveBudget.descriptionTokens) tok · 正文 \(liveBudget.bodyLines)/\(Budget.maxBodyLines) 行")
                .foregroundStyle(liveBudget.isOverBudget ? V2.amber : V2.textDim)
                .help("按编辑器里当前的内容计算，而不是已保存的文件：描述的 token 数，以及正文行数与建议上限的对比")
            Text(model.isDirty ? "已编辑" : "已保存")
                .foregroundStyle(model.isDirty ? V2.amber : V2.textDim)
                .help(model.isDirty
                      ? "编辑器里有尚未写入文件的更改"
                      : "磁盘上的文件和编辑器里的内容一致")
        }
        .font(.system(size: 11))
        .monospacedDigit()
        .foregroundStyle(V2.textDim)
        .padding(.horizontal, 12)
        .frame(height: Self.editorStatusBarHeight)
        .background(V2.footer)
        .overlay(alignment: .top) { Hairline(color: Color.white.opacity(0.07)) }
    }

    // MARK: - Shared pieces

    private func cardHeader<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack {
            content()
            Spacer()
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { Hairline(color: Color.white.opacity(0.08)) }
    }

    private func icon(for kind: ItemKind) -> String {
        switch kind {
        case .skill: return "doc.text"
        case .command: return "terminal"
        case .agent: return "person.2"
        case .mcp: return "network"
        case .plugin: return "puzzlepiece.extension"
        }
    }
}

/// The document toolbar's buttons: quiet pill normally, accent-filled for the one primary
/// action, both fading out instead of vanishing while there is nothing to act on.
struct V2ToolbarButtonStyle: ButtonStyle {
    var prominent: Bool
    var enabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            // "Revert" clipped to "R" is not a smaller button, it is a broken one. The bar around
            // it drops whole items instead of letting its labels dissolve.
            .fitsOnOneLine()
            .foregroundStyle(
                enabled ? (prominent ? Color.white : Color.white.opacity(0.85)) : Color.white.opacity(0.28)
            )
            .padding(.horizontal, prominent ? 12 : 11)
            .frame(height: 24)
            .background(
                enabled ? (prominent ? V2.accent : V2.button) : Color.clear,
                in: RoundedRectangle(cornerRadius: 7)
            )
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(
                Color.white.opacity(enabled && prominent ? 0.14 : 0.08), lineWidth: 0.5
            ))
            .contentShape(RoundedRectangle(cornerRadius: 7))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
