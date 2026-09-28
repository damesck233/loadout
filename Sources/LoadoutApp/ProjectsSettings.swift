import AppKit
import SwiftUI
import LoadoutCore

/// Where Loadout looks for repositories.
///
/// This is the whole of what a person has to keep up to date, and it is deliberately the short
/// list: two or three folders, chosen once. What is inside them is worked out on every launch, so a
/// repository cloned this morning is in the list this afternoon with nobody maintaining anything.
///
/// It replaced a single generated file, `~/Projects/INDEX.md`, that one person kept by hand.
/// Reading it was worse than useless to everybody else: they opened the app to no projects and no
/// explanation, because their global skills filled the list and nothing said the other half was
/// behind a control they had never pressed. Hence the footnote naming that control out loud — and
/// hence one source here, not two, so this screen never has to describe somebody's habit.
struct ProjectsSettings: View {
    @Bindable var model: AppModel

    /// Repositories per folder, counted off the main thread. Walking three levels of directories
    /// inside `body` meant every redraw of this pane re-walked every folder.
    @State private var counts: [URL: Int] = [:]

    var body: some View {
        SettingsGroup(
            title: "项目放在哪里",
            // The depth is interpolated, not spelled out: the sentence said two while the search
            // went three deep, and the row below it printed the real number two lines away.
            note: "Loadout 会在这些文件夹里查找代码仓库，也就是含有 .git 或 .claude 的文件夹，"
                + "最多向下 \(ProjectRoots.searchDepth) 层。文件夹本身是仓库的也算，"
                + "所以可以直接指向你正在做的项目。",
            footnote: "在列表上方的范围按钮里选中某个项目后，就能看到它自己的技能和命令。"
        ) {
            ForEach(model.projectRoots.folders, id: \.self) { folder in
                SettingsRow(
                    label: ProjectRoots.abbreviate(folder, home: model.paths.home),
                    sub: countIn(folder),
                    mono: true
                ) {
                    SettingsLinkButton(
                        title: "移除",
                        help: "不再查找 \(ProjectRoots.abbreviate(folder, home: model.paths.home))"
                    ) {
                        model.setProjectRoots(model.projectRoots.folders.filter { $0 != folder })
                    }
                }
            }

            // The count sits on this row on purpose, next to the thing that produces it. It was
            // briefly here while a second, hidden source was also feeding the list, which made it
            // read as a lie: "nothing chosen" over "89 projects found".
            SettingsRow(
                label: model.projectRoots.folders.isEmpty ? "选择第一个文件夹" : "再添加一个文件夹",
                sub: model.projectRoots.folders.isEmpty
                    ? "选好之前，只列出全局加载的内容"
                    : found,
                dividing: false
            ) {
                Button("选择…") { add() }
                    .buttonStyle(V2ToolbarButtonStyle(
                        prominent: model.projectRoots.folders.isEmpty, enabled: true
                    ))
                    .help("选择存放代码仓库的文件夹，也可以直接选某个仓库")
                    .pointingHand()
            }
        }

        SettingsGroup(
            title: "扫描",
            footnote: "每次启动时读取，改动这些文件夹后也会重新读取。"
                + "Loadout 只看不写，不会往你的仓库里写任何东西。"
        ) {
            SettingsRow(label: "查找深度") {
                SettingsValue(text: "\(ProjectRoots.searchDepth) 层")
            }
            SettingsRow(
                label: "怎样算一个项目",
                sub: "含有 .git 或 .claude 的文件夹",
                dividing: false
            ) {
                EmptyView()
            }
        }
        .onAppear { countRepositories() }
        .onChange(of: model.projectRoots.folders) { _, _ in countRepositories() }
    }

    private var found: String {
        let count = model.projects.count
        return "找到 \(count) 个项目"
    }

    /// How many projects came out of this folder in particular, so a folder that turned out to
    /// hold nothing says so instead of sitting there looking fine.
    /// Reads the count worked out off the main thread rather than walking the disk here: this is
    /// called from `body`, and counting means three levels of directory listing per folder.
    private func countIn(_ folder: URL) -> String {
        guard let count = counts[folder] else { return "正在统计…" }
        guard count > 0 else { return "这里没有找到代码仓库" }
        return "\(count) 个项目"
    }

    private func countRepositories() {
        let home = model.paths.home
        let folders = model.projectRoots.folders
        Task.detached(priority: .userInitiated) {
            var found: [URL: Int] = [:]
            for folder in folders {
                found[folder] = ProjectRoots(folders: [folder]).discover(home: home).count
            }
            await MainActor.run { counts = found }
        }
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
}
