# Boxmail

<img src="Sources/BoxmailCore/Resources/BoxmailMark.png" alt="Boxmail" width="80" height="80">

Boxmail 是原生 macOS AI 邮件客户端，使用 SwiftUI、本机 Node.js 和 SQLite，支持 IMAP/SMTP 与 BYOK AI，兼容 OpenAI Responses、Chat Completions 和 Anthropic Messages。

当前发布为 **0.1.9（build 48）**，源码标签为 `v0.1.9`，安装包见 [GitHub Release](https://github.com/lock-down/Boxmail/releases/tag/v0.1.9)。版本以 [VERSION](VERSION) 和 [BUILD](BUILD) 为准。本版发布整封 AI 上下文、共享组件和收件人滚动修复，具体范围及验证见 [变更记录](CHANGELOG.md#019--2026-11-13)。

「整封理解」与 AI 回复共用正文、全部可读附件及 ZIP 子项，一次提交原始资料并展示文件覆盖范围。邮件头、正文引用和转发预览共用收件信息组件，长名单展开为 240 pt，滚轮跟随鼠标所在区域。界面、分页、设置动作与双端规则的合并结论见 [代码审查](docs/CODE_REVIEW.md)。

## 功能

- 多账户收发、HTML 与内嵌图片阅读、可恢复的历史同步、引用链会话。
- 同一发件人聚合折叠，默认开启，组间及组内均按最新时间倒序，可切回逐封显示；展开后分页查看历史邮件。
- 最多两个账户并行同步，清单与下载分别显示进度，超时后保留断点；“设置 > 开发者”可导出脱敏诊断日志。
- 紧凑邮件列表、原生连续及离散多选、批量归档／删除／标记／分类，以及最近一次手动操作的即时撤销；支持键盘切换邮件、搜索和批量处理。
- 富文本草稿、字号与颜色、粗体、列表与链接、联系人补全、回复与转发、个人签名、附件选择与粘贴，发送前确认；IMAP 草稿同步保留双方编辑冲突，正文按需加载，转发原文独立保存。
- 逐步显示的整封理解、原排版翻译、回复预览、写信、附件理解和分类整理；总结列表可单项或多选移除、清空及恢复，邮件内的 AI 结果保留。
- 会话 AI 总结往来进展、未决事项及下一步，提供依据邮件跳转与上下文回复预览，新回信到达后提示刷新。
- 中文全文与组合条件搜索、本机草稿搜索、自定义分类，以及基于 pi-ai 1.3.0 的多服务商 BYOK、协议选择、模型能力及推理等级配置。
- 配置与密钥迁移、完整备份恢复、自定义数据目录及搜索索引重建；导入前展示邮箱主机与凭证处理方式，端点变化后提示重填凭证。

阅读区提供整封理解、翻译、AI 回复和会话 AI，附件区也可进入整封理解，已保存的单封总结统一从“摘要集合”进入。写信正文上方可设置字号、颜色、粗体、列表和链接，草稿箱与写信窗口均提供“同步草稿”。窄窗口从左上角打开邮箱导航，写信中的 AI、抄送与密送按需展开。设置统一使用“取消／保存”，邮箱账户单独保存；搜索显示范围与返回入口，返回附件页面后保留局部筛选。具体操作见使用指南。

## 开发运行

开发需要 macOS、Swift 6.0 或更高版本、Node.js 24.22.2 LTS 或更新的 LTS 版本及 npm。构建、测试和后端启动时会检查 Node.js 版本，App 内置构建时通过检查的运行时。在仓库根目录执行：

```bash
./script/build_and_run.sh
```

脚本安装缺失的后端依赖，编译并打包本机服务及运行时，关闭已运行的 Boxmail，再启动 `dist/Boxmail.app`。日常开发版默认不生成演示数据，隔离验收模式 `--review` 保留演示数据。Codex Run 使用同一入口；`swift run` 不会准备 App 所需的后端资源。

```bash
./script/test.sh
```

测试源码与样例仅保留在本地，`Tests/` 和 `Backend/test/` 不进入 Git；新检出需先准备这些目录才能运行回归。测试脚本先构建 PPT 原生渲染组件，再运行后端和 Swift 测试，缺少目录时会明确退出。联调、签名及发布步骤见 [开发说明](docs/DEVELOPMENT.md)。

当前源码回归覆盖 ZIP 与备份损坏缓存恢复、草稿异常和并发对账、工作区分页、预览临时文件清理、富文本连续编辑、窗口缩放，以及控件对齐、表格断点和面板边界。0.1.9 完整回归通过 465 项后端和 224 项 Swift 测试，发布前 UI 检查未发现新增问题；验证范围见[本版变更](CHANGELOG.md#019--2026-11-13)，复现方法见[开发说明](docs/DEVELOPMENT.md)。历史验证基线保留在对应版本条目中。

## 安装包

从干净且已提交的工作区执行：

```bash
./script/package_app.sh
```

产物位于 `dist/`，文件名为 `Boxmail-v<版本>-macos-<架构>-clean.zip`，附 SHA-256 校验文件。包内包含 App、Node.js、生产依赖、使用说明和记录完整源码提交号的版本信息；新安装关闭演示数据，已有用户数据继续保留。

项目声明最低 macOS 14；本次发布在 Apple Silicon、macOS 27.2.1、Swift 6.4.2、Node.js 26.13.1 LTS 环境验证。最低系统、Intel Mac 及其他设备尚未验证，当前使用本机临时签名，尚未完成 Developer ID 签名和公证。安装与首次配置见 [使用指南](docs/USER_GUIDE.md)。

## 文档

| 文档 | 内容 |
| --- | --- |
| [使用指南](docs/USER_GUIDE.md) | 安装、邮箱与 AI 配置、邮件操作、搜索、附件、数据迁移和常见问题；同时随安装包分发 |
| [开发说明](docs/DEVELOPMENT.md) | 源码入口、测试、界面约定、本机凭证、签名、打包及版本维护 |
| [UI 规范](docs/DESIGN.md) | 颜色、字体、布局、共用组件、交互状态、动效、可访问性和界面验收 |
| [后端接口](Backend/README.md) | 独立启动、环境变量、HTTP API、任务和数据契约 |
| [开发路线](docs/ROADMAP.md) | 已完成的优先功能、后续候选及参考项目 |
| [代码审查](docs/CODE_REVIEW.md) | 已完成的合并、保留边界与维护入口 |
| [整封邮件 AI 上下文](docs/MAIL_AI_CONTEXT.md) | 正文与附件联合理解、模型调用、覆盖范围及兼容边界 |
| [变更记录](CHANGELOG.md) | 各版本变化、代码审查修复及验证范围 |

当前行为写入对应指南，变更记录按版本记录用户可见变化；历史实现可从 Git 提交与标签追溯，安装包见各版本 GitHub Release。

## 项目结构

```text
app.png                              品牌原始素材
Sources/Boxmail/                      SwiftUI 界面、状态、本机凭证及后端生命周期
Sources/BoxmailCore/                  数据模型、共享资源及本机存储逻辑
Sources/BoxmailPresentationRenderer/  PPT 本机逐页渲染
Backend/src/                         HTTP、SQLite、邮件协议、AI 和附件处理
Backend/test/                        本地后端回归和合成样例，不跟踪
Tests/                               本地 Swift 回归，不跟踪；存在时自动启用测试目标
docs/                                使用指南、UI 规范、开发说明及路线
script/                              构建、启动、测试、打包和图标生成
```

默认数据目录为 `~/Library/Application Support/Boxmail/`。邮箱授权码和 API Key 保存在该目录的 `.env` 文件，设置界面自动读写，同步、发信和 AI 调用无需钥匙串授权。文件以明文保存，App 写入时权限为 `0600`，可从“设置 > 高级 > 本机数据 > 显示凭证文件”定位。服务器地址、模型及偏好继续由设置界面保存。

如需使用仓库内的配置文件，可参考 [.env.example](.env.example)：

```bash
cp .env.example .env
BOXMAIL_ENV_FILE="$PWD/.env" ./script/build_and_run.sh
```

`BOXMAIL_ENV_FILE` 必须是绝对路径，省略时使用当前数据目录下的 `.env`。旧钥匙串凭证不会自动读取；升级后重新填写并保存授权码、API Key，或导入此前导出的配置 JSON。完整 ZIP 备份不包含 `.env`；默认位置的文件随数据目录迁移，外部指定文件保留在原位置。调用云端 AI 会将任务所需邮件或附件内容提交给所配置的服务商。本机邮件缓存、凭证文件、完整备份和配置导出均未加密，具体范围见使用指南。
