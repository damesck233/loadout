import SwiftUI
import LoadoutCore

/// The five themes, and how a document reads.
///
/// The theme choice is a colour, so the control is the colour — but each disc is named as well,
/// because a ring around a circle says *which* one is on and never what it is called. Picking one
/// repaints the window behind this pane on the spot, which is the only preview worth having and the
/// best argument for Settings living in the window rather than over it.
struct AppearanceSettings: View {
    private let themes = ThemeStore.shared
    // The same three keys the reading pane and the ⌘+/− menu use. This is where a hand looks for
    // text size, and a preferences screen holding only five circles reads as unfinished.
    @AppStorage("readerFontSize") private var readerFontSize = 15.0
    @AppStorage("readerFont") private var readerFont = "system"
    @AppStorage("readerBackground") private var readerBackground = "darker"
    @AppStorage("listDensity") private var density = "compact"

    var body: some View {
        SettingsGroup(
            title: "主题",
            note: themes.name.hint,
            footnote: "选中后窗口立即变化，下次启动时仍会沿用。"
        ) {
            HStack(spacing: 18) {
                ForEach(ThemeName.allCases) { theme in
                    swatch(theme)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
        }

        SettingsGroup(
            title: "列表",
            footnote: "紧凑模式去掉描述，行距也更紧。有八十个技能时，正是这些描述让一栏变成一堵墙，"
                + "如果你叫得出自己每个技能的名字，描述只会让你多滚几屏。"
        ) {
            SettingsRow(label: "密度", dividing: false) {
                Picker("", selection: $density) {
                    Text("宽松").tag("comfortable")
                    Text("紧凑").tag("compact")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
                .pointingHand()
            }
        }

        SettingsGroup(
            title: "阅读",
            footnote: "在任何地方按 ⌘+ 和 ⌘− 都能调整大小，⌘0 恢复默认。"
        ) {
            SettingsRow(label: "文字大小") {
                HStack(spacing: 10) {
                    Slider(value: $readerFontSize, in: 12...22, step: 1)
                        .frame(width: 160)
                        .pointingHand()
                    SettingsValue(text: "\(Int(readerFontSize)) pt")
                }
            }
            SettingsRow(label: "字体") {
                Picker("", selection: $readerFont) {
                    Text("系统").tag("system")
                    Text("衬线").tag("serif")
                    Text("等宽").tag("mono")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
                .pointingHand()
            }
            SettingsRow(
                label: "阅读背景",
                sub: "右侧面板里文档下面的底色",
                dividing: false
            ) {
                Picker("", selection: $readerBackground) {
                    Text("卡片").tag("card")
                    Text("更暗").tag("darker")
                    Text("墨黑").tag("ink")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
                .pointingHand()
            }
        }
    }

    private func swatch(_ theme: ThemeName) -> some View {
        let selected = themes.name == theme
        return Button {
            themes.name = theme
        } label: {
            VStack(spacing: 7) {
                Circle()
                    .fill(theme.palette.accent)
                    .frame(width: 30, height: 30)
                    // A hairline of its own, so Graphite's grey still reads as a disc against the
                    // pane's own grey — and the selected ring sits outside the disc, across a gap
                    // in the window colour, rather than on top of it.
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.25), lineWidth: 0.5))
                    .padding(2)
                    .overlay {
                        Circle().strokeBorder(
                            selected ? Color.white.opacity(0.9) : Color.clear, lineWidth: 3.5
                        )
                    }
                Text(theme.label)
                    .font(.system(size: 11))
                    .foregroundStyle(selected ? Color.white.opacity(0.9) : V2.textFaint)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(theme.hint)
        .accessibilityLabel(theme.label)
        .pointingHand()
    }
}
