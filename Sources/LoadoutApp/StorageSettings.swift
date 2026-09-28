import SwiftUI
import LoadoutCore

/// What Loadout has left on disk, and clearing it.
///
/// Before every edit the app copies the file, which is the only reason a mistake is survivable —
/// and for a long time nothing ever removed a copy, so a year of editing left a year of copies and
/// the only way to notice was to go looking at your own disk. Sweeping now happens at every launch;
/// this screen is where you see what is there and clear it on demand.
struct StorageSettings: View {
    @Bindable var model: AppModel

    @State private var isCounting = false
    @State private var report = Housekeeping.Report()
    @State private var isClearing = false
    @State private var confirming = false
    @State private var resultMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            groups
        }
        .task { await recount() }
        .alert("立即清理？", isPresented: $confirming) {
            Button("取消", role: .cancel) {}
            Button("清理", role: .destructive) { Task { await sweep() } }
        } message: {
            Text(
                "超过 30 天的备份副本会移到废纸篓，已不存在的内容留下的记录会被清除。"
                + "你写的内容不会被动到。"
            )
        }
    }

    @ViewBuilder
    private var groups: some View {
        SettingsGroup(
            title: "Loadout 保存的内容",
            note: "每个即将修改的文件都会先存一份副本，另外还有一些小记录，"
                + "让停用的内容能原样恢复。",
            footnote: "超过 30 天的副本会在启动时移到废纸篓，清倒废纸篓之前都不会真的消失。"
        ) {
            SettingsRow(label: "快照") {
                if isCounting {
                    ProgressView().controlSize(.small)
                } else {
                    SettingsValue(text: "\(report.snapshots)")
                }
            }
            SettingsRow(label: "占用空间") {
                SettingsValue(
                    text: ByteCountFormatter.string(fromByteCount: report.bytes, countStyle: .file)
                )
            }
            if report.strandedRecords > 0 {
                SettingsRow(
                    label: "已不存在的内容留下的记录",
                    sub: "这台 Mac 上已经没有东西用到它们"
                ) {
                    SettingsValue(text: "\(report.strandedRecords)")
                }
            }
            SettingsRow(label: "文件夹", mono: true) {
                SettingsLinkButton(title: "在访达中显示", help: model.paths.backups.path) {
                    model.revealBackups()
                }
            }
            SettingsRow(
                label: "立即清理",
                sub: report.isEmpty ? "现在没有需要清理的内容" : resultMessage,
                dividing: false
            ) {
                Button("清理") { confirming = true }
                    .buttonStyle(V2ToolbarButtonStyle(
                        prominent: false, enabled: !(isClearing || isCounting || report.isEmpty)
                    ))
                    .disabled(isClearing || isCounting || report.isEmpty)
                    .pointingHand(enabled: !(isClearing || isCounting || report.isEmpty))
            }
        }

        if !report.unreadableRecords.isEmpty {
            SettingsGroup(
                title: "无法读取",
                note: "这些是 Loadout 自己的记录，里面可能记着某些已停用的内容。",
                // Never swept, on purpose: a file nobody can read is a question, and deleting it
                // answers it the wrong way.
                footnote: "原因查明之前不会清理它们，免得丢东西。"
            ) {
                ForEach(Array(report.unreadableRecords.enumerated()), id: \.element) { index, url in
                    SettingsRow(
                        label: url.lastPathComponent,
                        mono: true,
                        dividing: index < report.unreadableRecords.count - 1
                    ) {
                        SettingsLinkButton(title: "在访达中显示") { model.revealBackups() }
                    }
                }
            }
        }
    }

    private func recount() async {
        isCounting = true
        let housekeeping = Housekeeping(paths: model.paths)
        // Sizing every snapshot walks the whole tree, which is why this is a task and not a
        // computed property: on a big backups folder it is tens of milliseconds of I/O.
        report = await Task.detached(priority: .utility) { housekeeping.report() }.value
        isCounting = false
    }

    private func sweep() async {
        isClearing = true
        let housekeeping = Housekeeping(paths: model.paths)
        let done = await Task.detached(priority: .utility) {
            (try? housekeeping.sweep()) ?? Housekeeping.Report()
        }.value
        resultMessage = describe(done)
        isClearing = false
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
