<p align="center">
  <img src="Resources/logo-light.png#gh-light-mode-only" width="280" alt="Loadout"><img src="Resources/logo-dark.png#gh-dark-mode-only" width="280" alt="Loadout">
</p>

<h1 align="center">Loadout 中文版</h1>

<p align="center">
  <strong>看清并管理你的编程助手到底加载了什么。</strong><br><br>
  本机所有助手的技能、斜杠命令、子代理、插件和 MCP 服务器都列在一处，<br>
  每一项实际触发过几次一目了然，自己写的那些还能直接编辑。
</p>

<p align="center">
  这是 <a href="https://github.com/migsilva89/loadout">migsilva89/loadout</a> 的简体中文汉化 fork，功能与上游一致，只翻译了界面和文档。<br>
  上游官网：<a href="https://loadout.migsilva.dev"><strong>loadout.migsilva.dev</strong></a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-15%2B-blue?style=flat-square" alt="macOS 15 或更高">
  <img src="https://img.shields.io/badge/Swift-6-orange?style=flat-square" alt="Swift 6">
  <img src="https://img.shields.io/badge/license-MIT-lightgrey?style=flat-square" alt="MIT 许可证">
  <a href="https://buymeacoffee.com/migsilva?utm_source=github-loadout">
    <img src="https://img.shields.io/badge/Buy%20me%20a%20coffee-%E2%98%95-FFDD00?style=flat-square" alt="请原作者喝杯咖啡">
  </a>
</p>

<p align="center">
  <img src=".github/assets/loadout-all.gif" width="1000" alt="浏览清单，停用再启用一个技能，单独关掉插件里的一个技能，把技能共享给第二个助手，然后让助手改写技能描述并在文档里接受修改">
</p>

## 功能

- **完整清单**：个人技能、项目技能、插件带来的一切、斜杠命令、子代理、MCP 服务器，本机每个助手的都在。Claude Code、Codex 和 Antigravity 的 MCP 服务器并排显示，每一项都标明归属。
- **真实用量**：每一项触发过几次、最近一次是什么时候、在几个项目里用过。数据直接读自助手自己的会话日志。
- **不虚报的计数**：如果某种历史格式没法证明一次调用确实发生过，就标成“格式不支持”，不会报一个看起来像“从没用过”的 0。
- **项目范围**：回答“在这个文件夹里打开助手，它能看到什么？”。另有一个“全部”列表，把你的和每个项目的并排列出，每行都写明它放在哪。想不起“那个技能我放哪了”的时候用它。
- **什么都能关**：单独关掉一个技能、命令、子代理或 MCP 服务器，不用删除。一个 38 项的插件，也可以只关其中一个技能，插件更新后 Loadout 会重新应用你的选择。
- **Codex 插件**：已安装的插件和它们的技能跟 Claude 的列在一起，开关各自独立。关掉整个插件，里面的技能全部显示为关闭；再打开时恢复你之前对每个技能的设置。Codex 本地插件开关需要装了支持插件清单协议的 Codex 版本。工作区统一管理的插件开关仍在 Codex 里操作。
- **编辑器**：新建、编辑、删除技能、命令和子代理，带语法高亮，并按官方文档的限制实时校验。
- **编辑器旁边的对话**：让 `claude`、`codex`、`opencode` 或 `agy` 改一个技能。它提出修改，你逐条决定要不要。
- **从仓库拿到自己手里**：放在某个项目里的技能、命令或子代理，点一下就能变成你全局可用的。这是复制，项目里那份还在，别人下次 pull 不会少任何东西。
- **帮助就在问题旁边**：设置 › 帮助用大白话说明关掉一项会对你的文件做什么、Loadout 自己的文件放在哪，报告问题时版本和系统信息已经替你填好。
- **每次写入前先备份**：备份失败就什么都不写。删除是移到废纸篓，从不 `rm`。
- **一个技能，所有助手**：用符号链接把同一份技能共享给多个助手，改一次处处生效。关掉时会问你要还给哪些助手，技能不会背着你换了主人。

## 安装

中文版需要从本仓库源码构建，要装好 Xcode：

```bash
git clone https://github.com/damesck233/loadout.git
cd loadout
./Scripts/build-app.sh
open dist/Loadout.app
```

然后把 `dist/Loadout.app` 拖进 `/Applications`。要求 macOS 15 或更高，Apple 芯片和 Intel 都行。

`brew install --cask migsilva89/loadout/loadout` 和上游 Releases 里的 DMG 装的都是英文原版。

关于自动更新：应用内置的 Sparkle 更新源指向上游英文版，接受更新会把中文版换回英文。所以这个 fork 默认关掉了自动检查更新。想跟进新版本，就拉取上游改动后重新构建。

## 聊聊你的配置

在任意标签页点“新建技能”旁边的“对话”。它调用你本机已经装好的助手 CLI，用的是你现有的订阅，不需要 API key。助手和模型在对话面板里选。

在某个技能上点“提问”，就把它附加到当前对话。可以附加好几个技能，也可以在输入框上方移除。选中别的行不会改变附件，也不会切换对话。移除附件后，之后的消息就不再带上它的文件，之前的消息仍留在对话里。“新对话”开一个没有附件的对话，“历史记录”里有以前的对话，包括全局对话功能上线前开的那些。

助手在附加文件夹的临时副本里工作。每条修改建议都在对话面板里点“接受”或“拒绝”，最后点“保存已接受的更改”。只有接受的修改会写回原文件，写之前先备份。如果文件在别处被改过，保存前要重新看一遍更新后的建议。插件文件只作只读参考。

在“新建技能”面板里，“用 Codex 编写”这类按钮会先生成骨架，再把它和你输入的内容一起交给助手当需求，描述和正文会以修改建议的形式回来。

## 在多个助手之间共享技能

每个助手都从 `~/.<名字>/skills` 读取技能，比如 `~/.claude/skills`、`~/.codex/skills`。Loadout 会自己找：只要这样的文件夹存在就会纳入，明天新装一个助手，不用改代码也能出现。Antigravity CLI（`agy`）是它知道的例外：它没有自己的文件夹，读的是 `~/.gemini/config/skills`，所以 Loadout 把它的技能放在那里。

点一个还没有该技能的助手，技能就会放过去。磁盘上的做法是：把文件夹提升到 `~/.agents/skills/<名字>`，再给每个助手建一个指向它的符号链接。只有一份，改一次，两边永远一致。点一个已点亮的标记，只会删掉那条链接，真正的那份永远不动。Loadout 菜单里的“全部同步到 <助手>”可以一次补齐。

如果两个助手各有一份同名技能，而且内容可能不同，应用不会自作主张地合并，会告诉你原因。

## 它会动哪些文件

| 数据 | 位置 | Loadout 会写吗？ |
|---|---|:---:|
| 你的技能、命令、子代理和 MCP 服务器 | `~/.claude/`、`~/.codex/`、`~/.gemini/config/`、`~/.<助手>/` | 只在你保存、新建、删除或共享时 |
| 每次写入前的备份 | `~/Library/Application Support/Loadout/backups/` | 会 |
| 用量索引，可重建 | `~/Library/Application Support/Loadout/usage.sqlite` | 会 |
| 助手对话用的工作副本 | `~/Library/Application Support/Loadout/ask-workspaces/` | 会 |
| 助手的会话日志 | `~/.claude/projects/`、`~/.codex/sessions/`、`~/.gemini/antigravity-cli/conversations/` | 从不，只读 |

Loadout 不把自己的文件放进 `~/.claude`。那个目录是 Claude 的，把数据库塞进别人的文件夹，迟早有人为了修点东西清空 `.claude` 时被坑一把。

应用本身不发任何网络请求。它替你调用的助手 CLI 会用你本机已有的凭据连接自己的服务商，Loadout 看不到这些凭据。

测试套件完全不碰上面这些位置：每个测试都跑在临时目录里，所以 `Paths` 的根目录是注入进去的。

Codex 插件的发现和配置修改走的是 Codex 本地的 app-server 协议，这些操作不会开启 AI 对话。想用已安装的 Codex 验证这部分集成，构建后运行 `.build/debug/LoadoutApp --self-check-codex`。它会建一个临时插件市场，测试单项开关、父级恢复、更新、备份以及配置保留。

## 安全

见 [SECURITY.md](SECURITY.md)。这里需要关注的是：写到预期目录之外、由文件内容驱动的命令执行，以及备份失败却没有阻止写入的任何路径。

## 贡献

汉化相关的问题（译文不准、漏翻、界面文字显示不全）欢迎在本仓库提 issue 或 PR。

功能和 bug 请提到上游 [migsilva89/loadout](https://github.com/migsilva89/loadout)。范围、测试方法和 PR 要求见 [CONTRIBUTING.md](CONTRIBUTING.md)。超出范围的功能写得再好也会被拒，所以请先开 issue。规格说明和逐条验收标准在 [docs/SPEC.md](docs/SPEC.md)。

## 状态

原作者的个人项目，有空就维护。能用，而且每天都在用，但不提供产品级的支持承诺。

上游的发布由 `./Scripts/release.sh` 构建。它拒绝在有未提交改动、没打 tag 的提交或非 `main` 分支上运行，签名之前会先跑测试。

## 支持原作者

Loadout 免费，以后也免费。如果它帮你省了时间，可以[请原作者喝杯咖啡](https://buymeacoffee.com/migsilva?utm_source=github-loadout)，下一个版本就有着落了。

## 许可证

[MIT](LICENSE)。
