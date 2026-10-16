# Boxmail 本机后端

版本 **0.0.4**。后端使用 Node.js 24 及其内置 SQLite，负责邮件同步、SMTP 发送、AI 任务、附件解析和本机持久化，由 macOS 客户端作为子进程启动。

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

当前工作区包含 61 项后端测试，覆盖邮件协议、连接诊断、HTML 和 CID 正文、旧缓存修复、Responses 参数、回复态度与预览、草稿复用、提示词、图片上传、PDF 页面转换、超时及临时文件清理，并覆盖 8 个长附件的完整上下文及断流保留结果。测试使用临时目录、模拟 IMAP/AI 和本机 TLS SMTP 服务。SMTP 测试需要系统提供 `openssl`，测试证书只用于本机测试。依赖版本固定在 `package-lock.json`。

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
| POST | `/agent` | `task`、`apiKey` 及任务参数；单封任务返回结果，`classify` 兼容入口返回后台任务 |
| POST | `/organize` | `accountId`、`apiKey`、`scope`（`unclassified` / `inbox`）、`limit`（1 至 200），立即返回后台任务 |
| GET | `/jobs/:id` | 单个任务及批次进度 |
| POST | `/jobs/:id/draft` | 把已完成的回复预览转为草稿，返回完整草稿；重复调用返回原草稿并保留编辑 |
| POST | `/jobs/:id/pause` | 中断当前批次，保留已完成建议 |
| POST | `/jobs/:id/retry` | `apiKey`，使用当前 AI 设置继续未完成邮件 |
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
| [mail-errors.js](src/mail-errors.js) | 区分认证、DNS、超时、证书与连接错误，不回显原始认证数据 |
| [mail-body.js](src/mail-body.js) | HTML 清理、正文文本转换、图片识别及缓存格式版本 |
| [agent.js](src/agent.js) | 任务编排、上下文、结果校验、摘要、草稿、分类确认与撤销 |
| [responses.js](src/responses.js) | Responses 请求、Files 上传、JSON / SSE 响应解析及临时文件清理 |
| [organizer.js](src/organizer.js) | 后台分批分类、进度保存、暂停与继续 |
| [ai-settings.js](src/ai-settings.js) | AI 默认配置和共享提示词读取 |
| [reply-presets.js](src/reply-presets.js) | 读取客户端共用的三种回复态度及其提示词 |
| [attachments.js](src/attachments.js) | 附件保存、读取、文本提取及 PDF 页面转换 |
| [validation.js](src/validation.js) | 账户、地址、收件人和 AI 配置校验 |
| [demo.js](src/demo.js) | 首次启动的演示数据 |

## AI 接口和附件理解

按照 [DeepSeek Responses API](https://api-docs.deepseek.com/zh-cn/api/create-response/) 发起请求：单封邮件与智能整理均使用 `stream: true` 的 SSE，读取 `response.completed` 完整结果，支持分块 UTF-8、保活事件和中断检测；仍兼容服务商返回普通 JSON 响应。通过 `instructions` 提供任务提示词，`input` 提供用户数据，`reasoning.effort` 传递 `low`、`high` 或 `max`，`text.format` 使用 JSON 模式。不发送温度、token 上限或原 Chat Completions 的参数。只读取完成响应中 assistant 消息的 `output_text`，忽略思考内容；响应未完成时保留已有结果；整理任务会按已完成数量标为 `partial` 或 `failed`。

单封总结、回复和翻译会附带本邮件各附件的名称、最多 16,000 字符提取文本及最多 16,000 字符已有分析，超过时分别标记截取。上下文整体按有效 JSON 序列化，不再对序列化结果直接裁切。网络断流会返回明确的重试提示，不使用部分输出覆盖原总结、译文或附件结果。

默认使用 `https://api.deepseek.com`、`deepseek-flash`、`high`、120 秒。超时范围为 10 至 600 秒，涵盖 Files 上传和 Responses 请求；客户端另留处理时间。旧配置启动时补齐 `effort` 和提示词，去掉旧的温度及 token 设置，保留自定义服务商、模型和提示词。

共享默认提示词位于 [DefaultPrompts.json](../Sources/BoxmailCore/Resources/DefaultPrompts.json)，通过构建脚本同时打包给 Swift 和 Node.js。用户编辑的提示词保存在设置中，空白值恢复为相应默认值。

回复任务支持可选 `replyPreset`：`interested`、`decline`、`thanks`，对应感兴趣回复、不感兴趣回复和感谢回复。态度说明位于共用的 [ReplyPresets.json](../Sources/BoxmailCore/Resources/ReplyPresets.json)，追加到用户自定义回复提示词之后；`prompt` 继续传入补充要求。未知态度会在模型调用前拒绝。

客户端发送 `task: "reply"`、`messageId`、`preview: true`，任务保留 `replyPreset`、`preview`，结果只含 `subject` 和 `body`，不会创建草稿。用户选择使用内容后，`POST /jobs/:id/draft` 创建草稿并回写 `result.draftId`，保存原邮件关联和回复线程。后续重复使用保留编辑；草稿删除或已进入发送流程时返回 `409`，原邮件缺失返回 `404`。旧客户端不传 `preview: true` 时仍直接生成待审核草稿。生成失败会保留此前成功的预览。

JPEG、PNG、GIF、WebP 通过 [Files API](https://api-docs.deepseek.com/zh-cn/api/create-file/) 以 `purpose=user_data` 上传，再通过 `input_image.file_id` 引用；上传设置一小时有效期，任务结束后尝试删除临时文件。PDF 使用已有 PDF 解析依赖转换页面为 PNG，无需 OCR 服务，每次最多 20 页，页面图片合计最多 25 MB；超限会提示拆分，不会静默遗漏页面。DOCX、XLSX 和文本附件提交提取内容，最多 60,000 字符，超过时在上下文中标明截断。

DeepSeek 目前只在 `deepseek-flash` 支持图片输入，选择 `deepseek-v4-pro` 解析图片会提示切换模型。其他服务商须同时支持此 Responses/Files 格式，实际兼容性需联调。


后台整理每批最多 6 封，使用主题、发件人及最多 600 字正文摘要；每批独立沿用设置中的超时与思考等级。任务保存 `messageIds`、`completedIds`、`progress`（`total`、`completed`、`failed`、`batchSize`、`batch`）及建议，不保存 API Key。重试只提交未完成 ID，忽略不属于当前批次的模型输出。`needsApproval`、`partial` 和 `paused` 状态中已有的建议可确认应用，应用后可撤销；`running` 状态不可应用。旧版失败任务没有批次信息，应重新开始整理。

翻译结果写入所属邮件的 `translation`，同步和跨文件夹移动保留译文。客户端的附件任务同时传入 `messageId`、`attachmentId`，后端校验归属；任务保存两者关联，并把所属邮件主题、发件人及最多 5,000 字正文加入附件理解上下文。

SQLite 使用 WAL 模式，当前 `user_version` 为 `1`。`records` 表按 `kind` 和 `id` 保存 JSON，`events` 表保存活动记录；附件文件存入数据目录的 `attachments/`。应用版本与数据库结构版本分别管理，后续结构变化需要补充迁移逻辑。

后端不会把邮箱密码或 API Key 保存到数据库；客户端从钥匙串读取后，在任务请求中传入。邮件缓存和附件为本机明文数据，文件访问权限不能替代加密。

账号安全连接沿用 `imapTLS` 和 `smtpTLS` 字段以兼容已配置账户：`true` 表示 SSL/TLS 直连，`false` 表示必须升级 STARTTLS。IMAP 和 SMTP 均启用服务器证书验证，账号 ID 和钥匙串凭证键保持不变。

连接测试分别验证 IMAP 和 SMTP，某一项失败时仍返回另一项的结果。认证失败会标明协议和服务器状态码；同步登录错误也使用相同说明。错误响应不包含授权码、认证载荷或原始服务器返回。

邮件记录同时保留纯文本 `body` 和已清理的 `html`，以 `bodyVersion: 1` 标记新版正文缓存。Mailparser 将 CID 图片转为本机 Data URL；HTML 仅保留阅读所需标签、属性和样式。同步发现旧缓存时重新读取邮件源，只补正文字段，不重建附件、不覆盖摘要或分类；完成后继续复用缓存。客户端启动发现旧正文缓存会执行一次同步，纯文本仍用于搜索、复制及 AI 上下文。

## 联调时需要保留的行为

同一账户不能并发同步；单封 AI 任务串行，同一账户最多一个后台整理任务，整理期间仍可使用单封 AI 功能，冲突请求返回 `409`。已读、星标及文件夹更改先记录本机操作，再于同步时提交；AI 分类只更新本机标签。邮件和附件内容作为模型输入，不作为后端可执行指令。

发送必须显式确认。草稿状态包括 `draft`、`sending`、`sent` 和 `uncertain`：发送成功后重复请求不会再次发送，结果不明确的草稿禁止自动重试。启动时把中断的发送标为 `uncertain`，把中断的单封 AI 任务标为失败，后台整理任务标为 `paused` 并保留建议和已完成 ID。SMTP 接受后归档失败会返回提示，不能据此再次发送。

全量同步、OAuth 和服务器草稿同步尚未实现。真实服务验证和版本提交流程见 [开发文档](../docs/DEVELOPMENT.md)。
