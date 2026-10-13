# Boxmail

Boxmail 是原生 macOS AI Agent 邮件客户端，使用 SwiftUI 构建界面，通过本机 Node.js 服务连接 IMAP/SMTP 邮箱，并调用可配置的 OpenAI 兼容模型接口。

当前版本为 **0.0.1**，用于后续开发、联调和修复的初始基线。版本号记录在 [VERSION](VERSION)，变更记录见 [CHANGELOG.md](CHANGELOG.md)。

## 运行项目

开发环境需要 macOS、Swift 6.0 或更高版本的工具链，以及 Node.js 24 或更高版本和 npm。项目声明的最低运行系统为 macOS 14；当前仅在 Apple Silicon、macOS 27.0.1、Swift 6.4、Node.js 24.21.0 环境验证过。

在仓库根目录运行：

```bash
./script/build_and_run.sh
```

脚本会安装缺失的后端依赖、编译 Swift 代码、生成图标、打包 Node.js 运行时和后端，并启动 `dist/Boxmail.app`。Codex 的 Run 按钮调用同一脚本。首次构建需要下载 npm 依赖；构建脚本会关闭当前运行的 Boxmail。

当前 App 使用本机临时签名，供开发验证，尚未完成正式签名、公证和分发。`swift run` 不会准备 App 所需的后端资源，日常启动请使用上述脚本。

## 首次配置

首次启动会创建演示邮箱和示例邮件，可以直接检查界面与本机操作。演示邮箱不能发送真实邮件，示例摘要也不代表模型调用结果。

1. 打开“设置 > 账号”，添加邮箱地址、登录用户名、IMAP/SMTP 主机、端口和 TLS 选项，填写邮箱授权码或服务商支持的密码。
2. 测试连接并保存账户，再执行同步；QQ、163 和企业邮箱均通过通用 IMAP/SMTP 接入，具体参数以服务商配置为准。
3. 打开“设置 > AI 助手”，填写 API 地址、API Key 和模型名称，测试连接后保存。
4. 在邮件详情中生成摘要或回复，在写信窗口检查草稿并确认发送；智能整理需确认后才应用本机分类，可撤销。

AI 接口地址填写服务商的 API 基地址，比如以 `/v1` 结尾的地址，服务会在其后追加 `/chat/completions` 和 `/models`。远程接口使用 HTTPS，本机模型允许回环地址 HTTP。模型名称需要填写，兼容性应通过连接测试确认。

调用云端 AI 时，任务所需的邮件或附件文本会发送到所配置的服务商。邮箱凭证和 API Key 保存在 macOS 钥匙串，不写入项目或邮件数据库。

## 0.0.1 的功能和范围

| 功能 | 当前行为 |
| --- | --- |
| 邮箱接入 | 通用 IMAP/SMTP，支持多个账户和连接测试 |
| 邮件阅读与同步 | 收件箱及服务商常用文件夹、已读、星标、移动和本机缓存 |
| 写信与发送 | 本机草稿、回复、转发、签名、附件、发送确认和发送结果记录 |
| AI 助手 | 摘要、待办、回复草稿、写信、分类建议、附件解析和翻译 |
| 邮件整理 | 分类预览、确认应用、撤销；分类标签保存在本机 |
| 附件与搜索 | 文本 PDF、DOCX、XLSX、TXT、CSV 等文本提取，邮件及附件文本搜索 |
| 设计参考 | Pencil MCP 导出的 19 个 HTML/CSS 页面及对应 PNG 预览 |

每个被识别的邮件文件夹同步最近 200 封邮件，尚未实现全量历史同步、IMAP IDLE、OAuth 登录、服务器草稿同步和扫描文档 OCR。单个附件限制为 25 MB，提取文本最多保留 200,000 个字符。正文采用文本阅读视图，尚未实现完整 HTML 邮件渲染。

真实邮箱服务商和真实 AI 服务仍需联调。最低系统版本、Intel Mac、正式签名和公证也尚未验证；登录启动、系统通知、本机垃圾邮件训练等能力尚未接入。

## 项目结构

```text
Sources/Boxmail/         SwiftUI 界面、状态管理、钥匙串、本机服务启动
Sources/BoxmailCore/     客户端与后端的数据模型
Tests/                  Swift 数据契约测试
Backend/src/            HTTP 接口、SQLite、邮件协议、AI、附件解析
Backend/test/           后端测试及本机 SMTP 集成测试
Design/Exports/         Pencil 导出的 HTML/CSS 设计参考
预览/                   19 个页面的 PNG 预览
script/                 构建、启动、测试和图标生成脚本
.codex/environments/    Codex Run 配置
```

SwiftUI 客户端通过带会话令牌的回环 HTTP 请求访问本机服务，后端负责邮件协议、AI 调用和 SQLite 持久化。客户端启动和关闭时管理后端子进程。接口和存储说明见 [Backend/README.md](Backend/README.md)，开发及版本流程见 [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)。

Pencil 导出页面作为原生实现的设计参考，App 不直接运行这些 HTML。页面索引见 [页面预览](页面预览.md)；原始 `AI-Mail.pen` 位于仓库同级目录，未包含在当前 Git 基线中。

## 数据与验证

默认数据目录为 `~/Library/Application Support/Boxmail/`，其中 `boxmail.sqlite` 保存邮件、草稿、设置和 AI 结果，`attachments/` 保存附件。缓存内容未做数据库加密。退出 App 后再备份整个目录，包含 SQLite 的关联文件；钥匙串凭证需单独管理。

```bash
npm ci --prefix Backend
./script/test.sh
./script/build_and_run.sh --verify
```

后端测试使用临时数据、本机协议服务和模拟 AI 响应，不访问真实邮箱、不发送真实外部邮件，也不产生云端 AI 调用费用。`--verify` 会启动 App 并检查进程是否存在，界面和真实服务联调仍需按开发文档检查。

`test.sh` 依次运行后端和 Swift 测试，并在当前工具链提供插件时显式加载 `TestingMacros`，处理 Command Line Tools 的测试宏加载问题。

Git 忽略 `.build/`、`dist/`、`Backend/node_modules/`、`artifacts/`、日志、数据库和本机环境变量文件。初始版本包含源码、依赖锁文件、测试及设计导出，构建产物可通过脚本重新生成。
