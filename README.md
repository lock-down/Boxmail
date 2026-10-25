# Boxmail

Boxmail 是原生 macOS AI 邮件客户端，使用 SwiftUI 构建界面，通过本机 Node.js 服务连接 IMAP/SMTP 邮箱，以 SQLite 保存本机数据，支持通过 BYOK 接入兼容 OpenAI Responses、Chat Completions 或 Anthropic Messages 的 AI 服务。

当前发布版本为 **0.0.31（build 32）**，源码标签为 `v0.0.31`，安装包见 [GitHub Release](https://github.com/lock-down/Boxmail/releases/tag/v0.0.31)。本版修复邮件与附件写入失败时的数据一致性问题，以及恢复备份后预览过期、旧响应覆盖新数据的问题；大响应的 JSON 处理移出界面主线程，待同步操作补齐超时与取消保护。版本号以 [VERSION](VERSION) 为准，发布历史统一记录在 [变更记录](CHANGELOG.md)。

## 功能

- 多账户收发、HTML 与内嵌图片阅读、可恢复的历史同步、引用链会话。
- 紧凑邮件列表、原生连续及离散多选、批量归档／删除／标记／分类，以及最近一次手动操作的即时撤销；支持键盘切换邮件、搜索和批量处理。
- 本机草稿、联系人补全、回复与转发、个人签名、附件选择与粘贴，发送前确认；HTML 转发保留原邮件排版，转发说明独立编辑，发送包含 HTML 与纯文本版本。
- 逐步显示的 AI 总结、原排版翻译、回复预览、写信、附件理解和分类整理；总结列表可单项或多选移除、清空及恢复，邮件内的 AI 结果保留。
- 中文全文与组合条件搜索、本机草稿搜索、自定义分类，以及基于 pi-ai 的多服务商 BYOK、协议选择、模型能力及推理等级配置。
- 配置与密钥迁移、完整备份恢复、自定义数据目录及搜索索引重建。

阅读区直接显示 AI 总结、翻译和 AI 回复，附件理解位于正文附件区，已保存的总结统一从“摘要集合”进入。列表底部显示同步状态与时间，缓存和服务器数量可展开查看；邮件行包含已读、附件和总结状态的无障碍描述。具体操作见使用指南。

## 开发运行

开发需要 macOS、Swift 6.0 或更高版本、Node.js 24 或更高版本及 npm。在仓库根目录执行：

```bash
./script/build_and_run.sh
```

脚本安装缺失的后端依赖，编译并打包本机服务及运行时，关闭已运行的 Boxmail，再启动 `dist/Boxmail.app`。Codex Run 使用同一入口；`swift run` 不会准备 App 所需的后端资源。

```bash
./script/test.sh
```

测试脚本先构建 PPT 原生渲染组件，再运行后端和 Swift 测试，使用临时数据及本机模拟服务。联调、签名及发布步骤见 [开发说明](docs/DEVELOPMENT.md)。

`node script/benchmark-startup.mjs` 测量隔离后端启动、首屏数据就绪及 RSS。0.0.26 的 2400 封合成邮件三轮交替测量中，后端及首屏数据就绪时间由 980 ms 降至 209 ms，就绪 RSS 由 353 MiB 降至 164 MiB；这是热缓存下的后端测量，不包含 SwiftUI、WebKit 和真实网络耗时，完整条件见开发说明。

0.0.31 完整回归通过 325 项后端测试和 103 项 Swift 测试，无失败或跳过。`node script/benchmark.mjs` 测量查询与同步耗时，`node script/benchmark-runtime.mjs` 测量同步、连续 AI、20 MB 图片和 20 页 PDF 的资源开销，均使用隔离数据与本机模拟服务。本轮另完成 120 个连续 AI 任务、12000 封邮件的原生验收及备份恢复检查；测量条件、结果及限制见开发说明。

## 安装包

从干净且已提交的工作区执行：

```bash
./script/package_app.sh
```

产物位于 `dist/`，文件名为 `Boxmail-v<版本>-macos-<架构>-clean.zip`，附 SHA-256 校验文件。包内包含 App、Node.js、生产依赖、使用说明和记录完整源码提交号的版本信息；新安装关闭演示数据，已有用户数据继续保留。

项目声明最低 macOS 14；最近发布在 Apple Silicon、macOS 27.0.1、Swift 6.4、Node.js 24.22.1 环境验证。最低系统、Intel Mac 及其他设备尚未验证，当前使用本机临时签名，尚未完成 Developer ID 签名和公证。安装与首次配置见 [使用指南](docs/USER_GUIDE.md)。

## 文档

| 文档 | 内容 |
| --- | --- |
| [使用指南](docs/USER_GUIDE.md) | 安装、邮箱与 AI 配置、邮件操作、搜索、附件、数据迁移和常见问题；同时随安装包分发 |
| [开发说明](docs/DEVELOPMENT.md) | 源码入口、测试、界面约定、钥匙串签名、打包及版本维护 |
| [后端接口](Backend/README.md) | 独立启动、环境变量、HTTP API、任务和数据契约 |
| [开发路线](docs/ROADMAP.md) | 已完成的优先功能、后续候选及参考项目 |
| [变更记录](CHANGELOG.md) | 版本变化、历史验收范围和标签归档 |

当前行为写入对应指南，历史变化只记录在变更记录中；不再为每个版本建立独立说明文件。

## 项目结构

```text
Sources/Boxmail/                      SwiftUI 界面、状态、钥匙串及后端生命周期
Sources/BoxmailCore/                  数据模型、共享资源及本机存储逻辑
Sources/BoxmailPresentationRenderer/  PPT 本机逐页渲染
Backend/src/                         HTTP、SQLite、邮件协议、AI 和附件处理
Backend/test/                        后端回归测试及合成附件样例
Tests/BoxmailCoreTests/               Swift 数据契约和行为测试
Tests/BoxmailTests/                   客户端导航、选择与分页状态回归
docs/                                使用指南、开发说明及路线
Design/Exports/                      19 个 HTML/CSS 设计参考
script/                              构建、启动、测试、打包和图标生成
```

默认数据目录为 `~/Library/Application Support/Boxmail/`，邮箱凭证和 API Key 保存在 macOS 钥匙串。调用云端 AI 会将任务所需邮件或附件内容提交给所配置的服务商。本机邮件缓存、完整备份和配置导出均未加密，具体范围见使用指南。
