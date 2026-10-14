# Boxmail

Boxmail 是原生 macOS AI Agent 邮件客户端，使用 SwiftUI 构建界面，通过本机 Node.js 服务连接 IMAP/SMTP 邮箱，并调用 DeepSeek Responses API 或同类兼容服务。

当前版本为 **0.0.3**，补齐 SSL/TLS 与 STARTTLS 选择、连接诊断、HTML 图片正文和正文滚动，保留 DeepSeek Responses、默认提示词及附件理解。`v0.0.1` 保留为初始基线，版本号记录在 [VERSION](VERSION)，变更记录见 [CHANGELOG.md](CHANGELOG.md)。

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

1. 打开“设置 > 账号”，添加邮箱地址、登录用户名、IMAP/SMTP 主机、端口，分别勾选“SSL/TLS”或“STARTTLS”，填写邮箱授权码或服务商支持的密码。
2. 测试连接并保存账户，再执行同步；QQ、163 和企业邮箱均通过通用 IMAP/SMTP 接入，具体参数以服务商配置为准。
3. 打开“设置 > AI 助手”，填写 API Key；默认地址为 `https://api.deepseek.com`，模型为 `deepseek-flash`，也可以配置其他兼容服务，测试连接后保存。
4. 在邮件详情中生成摘要或回复，在写信窗口检查草稿并确认发送；智能整理需确认后才应用本机分类，可撤销。

AI 接口地址填写服务商的 API 基地址，服务会在其后追加 `/responses`、`/models`，解析图片时使用 `/files`。远程接口使用 HTTPS，本机模型允许回环地址 HTTP。高级参数只有思考等级 `Low / High / Max` 和超时，默认 `High`、120 秒，超时范围为 10 至 600 秒。请求不发送温度或 token 上限参数，接口依据 [DeepSeek Responses 文档](https://api-docs.deepseek.com/zh-cn/api/create-response/)。

邮箱“SSL/TLS”使用连接时直接加密的方式，常用 IMAP 端口为 993、SMTP 端口为 465；“STARTTLS”在连接后升级加密，常用端口为 143 和 587。切换安全连接时只自动调整相应的常用端口，自定义端口会保留。旧版“TLS”勾选对应新版“SSL/TLS”，已有账号无需重新添加，两种方式均验证服务器证书。

“测试连接”会分别说明 IMAP 和 SMTP 的结果。若 QQ 返回登录拒绝或 SMTP `535`，说明服务器已接收连接但未通过登录认证；先核对邮箱地址和登录用户名的完整拼写，再确认网页版 IMAP/SMTP 服务已开启、授权码由当前邮箱生成且仍有效，输入后点击“保存账户”。账号异常或登录频率限制也可能导致相同返回，不能仅凭 `535` 判定授权码错误。

摘要、回复、写信、分类、附件理解和翻译均已填写默认提示词，可自定义、恢复当前默认；清空后保存会恢复默认。客户端和后端共用 `Sources/BoxmailCore/Resources/DefaultPrompts.json`，旧设置会自动补齐默认提示词并移除旧高级参数，自定义配置会保留。

调用云端 AI 时，任务所需的邮件、附件文本或图片会发送到所配置的服务商。邮箱凭证和 API Key 保存在 macOS 钥匙串，不写入项目或邮件数据库。

## 从 0.0.1 升级

运行构建脚本即可启动新版，现有本机邮件、附件和草稿会保留。启动时会移除旧的温度和 token 设置，补齐思考等级及默认提示词，保留自定义提示词和已配置的服务商、模型、超时；未配置的旧默认 AI 地址和模型会改用 DeepSeek。

AI 接口已从 Chat Completions 改为 Responses。原服务商如果仅支持 `/chat/completions`，需要在“设置 > AI 助手”切换为支持 `/responses` 的服务；图片和 PDF 理解还需要 Files 接口和视觉模型。升级后可先测试连接，再使用真实邮件进行联调。

## 开发版功能和范围

| 功能 | 当前行为 |
| --- | --- |
| 邮箱接入 | 通用 IMAP/SMTP，支持多个账户和连接测试 |
| 邮件阅读与同步 | HTML 排版、图片正文、内嵌图片、常用文件夹、已读、星标、移动和本机缓存 |
| 写信与发送 | 本机草稿、回复、转发、签名、附件、发送确认和发送结果记录 |
| AI 助手 | 摘要、待办、回复草稿、写信、分类建议、附件解析和翻译 |
| 邮件整理 | 分类预览、确认应用、撤销；分类标签保存在本机 |
| 附件与搜索 | 文档和图片理解，邮件、附件文本和 AI 解析结果搜索 |
| 设计参考 | Pencil MCP 导出的 19 个 HTML/CSS 页面及对应 PNG 预览 |

图片通过 Files API 上传，再以 `input_image.file_id` 交给模型；PDF 在本机转换为页面图片，支持扫描文档，每次最多 20 页；DOCX、XLSX、TXT、CSV 等提取文本交给模型，无需配置 OCR 服务。DeepSeek 的接口支持 JPEG、PNG、GIF、WebP 图片，PDF 和 Office 文件不能直接作为文件输入，详见 [Files API](https://api-docs.deepseek.com/zh-cn/api/create-file/)。图片理解需使用支持视觉输入的模型，DeepSeek 默认使用 `deepseek-flash`。

每个被识别的邮件文件夹同步最近 200 封邮件，尚未实现全量历史同步、IMAP IDLE、OAuth 登录和服务器草稿同步。单个附件及 PDF 转换后的图片合计限制为 25 MB，提取文本最多保留 200,000 个字符，单次附件 AI 分析最多提交 60,000 字符。

HTML 邮件使用 WebKit 显示表格、文字排版和图片，CID 内嵌图片直接从邮件内容读取。默认沿用“设置 > 阅读邮件 > 屏蔽远程图片”，可在正文上方点击“加载本封邮件图片”；关闭屏蔽后自动加载外部图片。邮件脚本、表单及嵌入页面会移除，链接在系统默认浏览器中打开。旧版仅保存文本的邮件会在同步时补回 HTML，不会清空本机摘要、标签或附件。

图片上传时设置一小时过期，并在任务完成或失败后尝试删除云端临时文件；清理失败时由 DeepSeek 按过期设置处理。本机附件和解析结果会保留。

已验证 QQ 邮箱的 SSL/TLS 登录、IMAP 同步、SMTP 认证，以及招商银行和 Discord 邮件的 HTML 正文显示。其他邮箱服务商和真实 AI 服务仍需联调。最低系统版本、Intel Mac、正式签名和公证也尚未验证；登录启动、系统通知、本机垃圾邮件训练等能力尚未接入。

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

0.0.2 验证记录：28 项后端测试、4 项 Swift 测试通过，App 构建、启动、本机签名和 Info.plist 检查通过；已检查思考等级、提示词编辑与恢复默认、附件页面操作。真实 DeepSeek 服务和邮箱服务商仍需联调。

0.0.3 验证记录：38 项后端测试、6 项 Swift 测试通过，补充连接错误分类、HTML 清理、内嵌图片、正文缓存迁移及旧数据契约测试，并在 QQ 邮箱检查连接、同步、图片正文、菜单整行点击和正文双向滚动。

Git 忽略 `.build/`、`dist/`、`Backend/node_modules/`、`artifacts/`、日志、数据库和本机环境变量文件。初始版本包含源码、依赖锁文件、测试及设计导出，构建产物可通过脚本重新生成。
