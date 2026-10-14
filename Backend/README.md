# Boxmail 本机后端

版本 **0.0.2**。后端使用 Node.js 24 及其内置 SQLite，负责邮件同步、SMTP 发送、AI 任务、附件解析和本机持久化，由 macOS 客户端作为子进程启动。

## 启动和测试

通常从仓库根目录执行 `./script/build_and_run.sh`，由客户端准备运行参数。单独联调后端时，可以在本目录运行：

```bash
npm ci
export BOXMAIL_DATA="${TMPDIR:-/tmp}/boxmail-dev"
export BOXMAIL_TOKEN="$(node -e "process.stdout.write(require('node:crypto').randomBytes(32).toString('hex'))")"
export BOXMAIL_PORT=56123
export BOXMAIL_DEMO=1
npm start
```

这会在指定目录建立独立的联调数据库，避免使用客户端的日常缓存；目录会保留，后续启动可以继续使用。进程启动后输出实际端口，按 Ctrl+C 关闭。

| 环境变量 | 用途 |
| --- | --- |
| `BOXMAIL_DATA` | 必填，数据库和附件所在目录 |
| `BOXMAIL_TOKEN` | 必填，至少 24 字符的会话令牌，客户端每次启动自动生成 |
| `BOXMAIL_PORT` | 监听端口，未设置或设为 `0` 时由系统分配 |
| `BOXMAIL_DEMO` | 默认建立演示数据，设为 `0` 关闭演示数据初始化 |

```bash
npm test
```

0.0.2 包含 28 项后端测试，覆盖邮件协议、Responses 参数、旧设置迁移、提示词、图片上传、PDF 页面转换、超时及临时文件清理。测试使用临时目录、模拟 IMAP/AI 和本机 TLS SMTP 服务。SMTP 测试需要系统提供 `openssl`，测试证书只用于本机测试。依赖版本固定在 `package-lock.json`。

## 接口

服务只监听 `127.0.0.1`。所有请求必须带 `X-Boxmail-Token`，请求体使用 JSON；带 `Origin` 的请求会被拒绝。成功返回 JSON，失败返回 `{ "error": "错误说明" }` 和对应 HTTP 状态码，请求体上限为 40 MB。

| 方法 | 路径 | 主要参数或行为 |
| --- | --- | --- |
| GET | `/state` | 账户、邮件、草稿、附件、任务、设置、活动及待同步数量 |
| GET | `/search` | `q`，可选 `accountId`，搜索邮件和附件文本 |
| POST | `/accounts/test` | `account`、`password`，测试 IMAP 和 SMTP |
| POST | `/accounts` | `account`，保存账户配置，不保存密码 |
| DELETE | `/accounts/:id` | 移除本机账户及关联缓存，保留服务器邮件 |
| POST | `/sync` | `accountId`、`password`，执行同步 |
| PATCH | `/messages/:id` | 更新 `unread`、`starred`、`folder` 或本机 `category` |
| POST | `/todos` | `messageId`、`todoId`、`done`，更新摘要待办 |
| POST | `/settings` | `ai`、`preferences`，保存配置 |
| POST | `/ai/test` | `config`、`apiKey`，实际请求一次模型生成 |
| POST | `/ai/models` | `config`、`apiKey`，读取模型列表 |
| POST | `/agent` | `task`、`apiKey` 及任务参数，执行 AI 任务 |
| POST | `/jobs/:id/approve` | 应用分类建议 |
| POST | `/jobs/:id/undo` | 撤销已应用的分类 |
| POST | `/drafts` | 保存本机草稿，可包含未填写完整的收件人 |
| DELETE | `/drafts/:id` | 删除可删除的本机草稿 |
| POST | `/send` | `draftId`、`password`、`approved: true`，确认发送 |
| POST | `/attachments` | `name`、Base64 `content`，可选关联 ID 和 `contentType` |
| GET | `/attachments/:id` | 返回 `name` 和 Base64 `content` |

数据字段以 [Swift 数据模型](../Sources/BoxmailCore/Models.swift)、[客户端调用](../Sources/Boxmail/Stores/MailStore.swift) 和 [接口实现](src/server.js) 为准；联调新增字段时同步修改两端。`/ai/test` 访问所配置的模型服务，可能产生该服务商的调用费用。

## 模块和持久化

| 模块 | 职责 |
| --- | --- |
| [server.js](src/server.js) | 认证、路由、请求限制、任务互斥及进程生命周期 |
| [database.js](src/database.js) | SQLite 记录、事务、搜索和活动记录 |
| [mail.js](src/mail.js) | IMAP 同步、邮件状态更改、SMTP 发送和已发送归档 |
| [agent.js](src/agent.js) | 任务编排、上下文、结果校验、摘要、草稿、分类确认与撤销 |
| [responses.js](src/responses.js) | Responses 请求、Files 上传、响应解析及临时文件清理 |
| [ai-settings.js](src/ai-settings.js) | AI 默认配置和共享提示词读取 |
| [attachments.js](src/attachments.js) | 附件保存、读取、文本提取及 PDF 页面转换 |
| [validation.js](src/validation.js) | 账户、地址、收件人和 AI 配置校验 |
| [demo.js](src/demo.js) | 首次启动的演示数据 |

## AI 接口和附件理解

按照 [DeepSeek Responses API](https://api-docs.deepseek.com/zh-cn/api/create-response/) 发起非流式请求，通过 `instructions` 提供任务提示词，`input` 提供用户数据，`reasoning.effort` 传递 `low`、`high` 或 `max`，`text.format` 使用 JSON 模式。不发送温度、token 上限或原 Chat Completions 的参数。只读取完成响应中 assistant 消息的 `output_text`，忽略思考内容；响应未完成时保留已有结果并将任务标为失败。

默认使用 `https://api.deepseek.com`、`deepseek-flash`、`high`、120 秒。超时范围为 10 至 600 秒，涵盖 Files 上传和 Responses 请求；客户端另留处理时间。旧配置启动时补齐 `effort` 和提示词，去掉旧的温度及 token 设置，保留自定义服务商、模型和提示词。

共享默认提示词位于 [DefaultPrompts.json](../Sources/BoxmailCore/Resources/DefaultPrompts.json)，通过构建脚本同时打包给 Swift 和 Node.js。用户编辑的提示词保存在设置中，空白值恢复为相应默认值。

JPEG、PNG、GIF、WebP 通过 [Files API](https://api-docs.deepseek.com/zh-cn/api/create-file/) 以 `purpose=user_data` 上传，再通过 `input_image.file_id` 引用；上传设置一小时有效期，任务结束后尝试删除临时文件。PDF 使用已有 PDF 解析依赖转换页面为 PNG，无需 OCR 服务，每次最多 20 页，页面图片合计最多 25 MB；超限会提示拆分，不会静默遗漏页面。DOCX、XLSX 和文本附件提交提取内容，最多 60,000 字符，超过时在上下文中标明截断。

DeepSeek 目前只在 `deepseek-flash` 支持图片输入，选择 `deepseek-v4-pro` 解析图片会提示切换模型。其他服务商须同时支持此 Responses/Files 格式，实际兼容性需联调。

SQLite 使用 WAL 模式，当前 `user_version` 为 `1`。`records` 表按 `kind` 和 `id` 保存 JSON，`events` 表保存活动记录；附件文件存入数据目录的 `attachments/`。应用版本与数据库结构版本分别管理，后续结构变化需要补充迁移逻辑。

后端不会把邮箱密码或 API Key 保存到数据库；客户端从钥匙串读取后，在任务请求中传入。邮件缓存和附件为本机明文数据，文件访问权限不能替代加密。

## 联调时需要保留的行为

同一账户不能并发同步，AI 任务串行执行，冲突请求返回 `409`。已读、星标及文件夹更改先记录本机操作，再于同步时提交；AI 分类只更新本机标签。邮件和附件内容作为模型输入，不作为后端可执行指令。

发送必须显式确认。草稿状态包括 `draft`、`sending`、`sent` 和 `uncertain`：发送成功后重复请求不会再次发送，结果不明确的草稿禁止自动重试。启动时把中断的发送标为 `uncertain`，把中断的 AI 任务标为失败。SMTP 接受后归档失败会返回提示，不能据此再次发送。

全量同步、OAuth 和服务器草稿同步尚未实现。真实服务验证和版本提交流程见 [开发文档](../docs/DEVELOPMENT.md)。
