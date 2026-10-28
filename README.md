# Boxmail

<img src="Sources/BoxmailCore/Resources/BoxmailMark.png" alt="Boxmail" width="80" height="80">

Boxmail 是原生 macOS AI 邮件客户端，使用 SwiftUI 构建界面，通过本机 Node.js 服务连接 IMAP/SMTP 邮箱，以 SQLite 保存本机数据，支持通过 BYOK 接入兼容 OpenAI Responses、Chat Completions 或 Anthropic Messages 的 AI 服务。

当前发布版本为 **0.1.2（build 37）**，源码标签为 `v0.1.2`，安装包见 [GitHub Release](https://github.com/lock-down/Boxmail/releases/tag/v0.1.2)。新增发件人聚合和开发者日志导出，修复多账户同步超时、取消与附件解析崩溃隔离。邮箱授权码与 API Key 继续使用本机 `.env`，同步、发信和设置保存无需钥匙串授权。桌面图标与客户端徽标沿用 `app.png` 的蓝紫色玻璃信封设计，邮件、AI、附件、搜索和本机数据能力继续保留；版本号以 [VERSION](VERSION) 为准，发布摘要见 [变更记录](CHANGELOG.md)。

## 功能

- 多账户收发、HTML 与内嵌图片阅读、可恢复的历史同步、引用链会话。
- 同一发件人聚合折叠，默认开启，组间及组内均按最新时间倒序，可切回逐封显示；展开后分页查看历史邮件。
- 最多两个账户并行同步，清单与下载分别显示进度，超时后保留断点；“设置 > 开发者”可导出脱敏诊断日志。
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

0.1.2 完整回归通过 351 项后端测试和 135 项 Swift 测试，无失败或跳过。新增覆盖六账户同步、崩溃隔离、取消请求、聚合刷新与数据库回滚，并隔离并行测试的 HTTP 会话；发布另检查资源、签名、安装包完整性和隔离启动退出。性能基准、故障恢复范围及联调边界统一见开发说明。

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
| [开发说明](docs/DEVELOPMENT.md) | 源码入口、测试、界面约定、本机凭证、签名、打包及版本维护 |
| [后端接口](Backend/README.md) | 独立启动、环境变量、HTTP API、任务和数据契约 |
| [开发路线](docs/ROADMAP.md) | 已完成的优先功能、后续候选及参考项目 |
| [变更记录](CHANGELOG.md) | 当前发布基线、变化及验证范围 |

当前行为写入对应指南，变更记录按版本记录用户可见变化；历史实现可从 Git 提交与标签追溯，安装包见各版本 GitHub Release。

## 项目结构

```text
app.png                              品牌原始素材
Sources/Boxmail/                      SwiftUI 界面、状态、本机凭证及后端生命周期
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

默认数据目录为 `~/Library/Application Support/Boxmail/`。邮箱授权码和 API Key 保存在该目录的 `.env` 文件，设置界面自动读写，同步、发信和 AI 调用无需钥匙串授权。文件以明文保存，App 写入时权限为 `0600`，可从“设置 > 高级 > 本机数据 > 显示凭证文件”定位。服务器地址、模型及偏好继续由设置界面保存。

如需使用仓库内的配置文件，可参考 [.env.example](.env.example)：

```bash
cp .env.example .env
BOXMAIL_ENV_FILE="$PWD/.env" ./script/build_and_run.sh
```

`BOXMAIL_ENV_FILE` 必须是绝对路径，省略时使用当前数据目录下的 `.env`。旧钥匙串凭证不会自动读取；升级后重新填写并保存授权码、API Key，或导入此前导出的配置 JSON。完整 ZIP 备份不包含 `.env`；默认位置的文件随数据目录迁移，外部指定文件保留在原位置。调用云端 AI 会将任务所需邮件或附件内容提交给所配置的服务商。本机邮件缓存、凭证文件、完整备份和配置导出均未加密，具体范围见使用指南。
