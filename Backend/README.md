# Boxmail 本机后端

版本 **0.0.12**。后端使用 Node.js 24 及其内置 SQLite，负责邮件同步、SMTP 发送、AI 任务、附件解析和本机持久化，由 macOS 客户端作为子进程启动。

当前代码随本地标签 `v0.0.12` 归档，文档入口见 [文档索引](../docs/README.md)。

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
| `BOXMAIL_PRESENTATION_RENDERER` | 可选，独立后端联调时指定 PPT 原生组件路径；App 自动使用内置组件 |

```bash
npm test
```

当前工作区包含 114 项后端测试，覆盖邮件协议、连接诊断、HTML 和 CID 正文、旧缓存修复、Responses 参数、回复态度与预览、草稿复用、提示词、图片上传、PDF 页面转换、超时及临时文件清理，并覆盖 8 个长附件的完整上下文及断流保留结果。模型列表测试覆盖缓存、重启、成功替换、空列表、失败保留及服务地址隔离；邮件整理测试覆盖删除与归档的来源、相同 Message-ID 副本、UID 变化、待处理移动、清空未下载邮件、互斥和附件引用保留。测试使用临时目录、模拟 IMAP/AI 和本机 TLS SMTP 服务。SMTP 测试需要系统提供 `openssl`，测试证书只用于本机测试。依赖版本固定在 `package-lock.json`。

完整验证从仓库根目录执行 `./script/test.sh`，它先构建 PPT 原生渲染组件再运行后端及 Swift 测试。单独运行 `npm test` 时，原生组件不可用会跳过对应渲染测试；合成文档及测试条件见 [样例说明](test/fixtures/README.md)。

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
| POST | `/messages/:id/restore` | 将已删除邮件恢复到来源文件夹 |
| POST | `/messages/:id/unarchive` | 取消归档并返回来源文件夹 |
| POST | `/trash/empty` | `accountId`、`password`、`approved: true`，清空当前账户全部已删除邮件 |
| POST | `/todos` | `messageId`、`todoId`、`done`，更新摘要待办 |
| POST | `/settings` | `ai`、`preferences`，保存配置 |
| POST | `/ai/test` | `config`、`apiKey`，实际请求一次模型生成 |
| GET | `/ai/models` | 可选查询参数 `baseURL`，读取对应地址的本机模型缓存，不访问服务商；省略时使用已保存地址 |
| POST | `/ai/models` | `config`、`apiKey`，请求服务商模型列表，成功后替换该地址的缓存，失败保留 |
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

App 从“设置 > 高级 > 本机数据”保存数据位置，启动后将实际位置通过 `BOXMAIL_DATA` 传给后端。目录迁移在服务启动前由客户端完成，使用 SQLite 一致性快照并重写附件绝对路径。App 与它启动的后端共同持有目录锁，退出中的服务释放锁后才能迁移或再次启动。独立后端联调应始终使用专门的临时目录，不与正在运行的 App 共用数据目录。

## 模块和持久化

| 模块 | 职责 |
| --- | --- |
| [server.js](src/server.js) | 认证、路由、请求限制、任务互斥及进程生命周期 |
| [database.js](src/database.js) | SQLite 记录、事务、搜索和活动记录 |
| [mail.js](src/mail.js) | IMAP 同步、邮件状态更改、SMTP 发送和已发送归档 |
| [mail-folders.js](src/mail-folders.js) | 文件夹识别、来源解析和待处理远端移动 |
| [mail-trash.js](src/mail-trash.js) | 清空服务器与本机已删除邮件，保留仍被引用的附件 |
| [mail-errors.js](src/mail-errors.js) | 区分认证、DNS、超时、证书与连接错误，不回显原始认证数据 |
| [mail-body.js](src/mail-body.js) | HTML 清理、正文文本转换、图片识别及缓存格式版本 |
| [agent.js](src/agent.js) | 任务编排、上下文、结果校验、摘要、草稿、分类确认与撤销 |
| [responses.js](src/responses.js) | Responses 请求、Files 上传、JSON / SSE 响应解析及临时文件清理 |
| [organizer.js](src/organizer.js) | 后台分批分类、进度保存、暂停与继续 |
| [ai-settings.js](src/ai-settings.js) | AI 默认配置和共享提示词读取 |
| [model-catalog.js](src/model-catalog.js) | 按规范化 API 地址读取与刷新模型列表缓存，不保存密钥 |
| [reply-presets.js](src/reply-presets.js) | 读取客户端共用的三种回复态度及其提示词 |
| [attachments.js](src/attachments.js) | 附件保存、读取、文本提取及 PDF / PPT 共用页面转换 |
| [presentations.js](src/presentations.js) | PPT / PPTX 系统预览、隐藏页处理、文本提取及原生组件调用 |
| [validation.js](src/validation.js) | 账户、地址、收件人和 AI 配置校验 |
| [demo.js](src/demo.js) | 首次启动的演示数据 |

## AI 接口和附件理解

按照 [DeepSeek Responses API](https://api-docs.deepseek.com/zh-cn/api/create-response/) 发起请求：单封邮件与智能整理均使用 `stream: true` 的 SSE，读取 `response.completed` 完整结果，支持分块 UTF-8、保活事件和中断检测；仍兼容服务商返回普通 JSON 响应。通过 `instructions` 提供任务提示词，`input` 提供用户数据，`reasoning.effort` 传递 `low`、`high` 或 `max`，`text.format` 使用 JSON 模式。不发送温度、token 上限或原 Chat Completions 的参数。只读取完成响应中 assistant 消息的 `output_text`，忽略思考内容；响应未完成时保留已有结果；整理任务会按已完成数量标为 `partial` 或 `failed`。

单封总结、回复和翻译会附带本邮件各附件的名称、最多 16,000 字符提取文本及最多 16,000 字符已有分析，超过时分别标记截取。上下文整体按有效 JSON 序列化，不再对序列化结果直接裁切。网络断流会返回明确的重试提示，不使用部分输出覆盖原总结、译文或附件结果。

默认使用 `https://api.deepseek.com`、`deepseek-flash`、`high`、120 秒。超时范围为 10 至 600 秒，涵盖 Files 上传和 Responses 请求；客户端另留处理时间。旧配置启动时补齐 `effort` 和提示词，去掉旧的温度及 token 设置，保留自定义服务商、模型和提示词。

共享默认提示词位于 [DefaultPrompts.json](../Sources/BoxmailCore/Resources/DefaultPrompts.json)，通过构建脚本同时打包给 Swift 和 Node.js。用户编辑的提示词保存在设置中，空白值恢复为相应默认值。

回复、写信、总结建议和附件理解中的邮件示例统一追加无签名的撰写规则，要求生成正文不包含署名段或签名占位符，也不复制输入中的签名段；正文与分析所需的联系人、提交邮箱和日期保留。该规则位于 `responses.js`，追加在任务提示词和回复态度之后，使用自定义提示词时同样生效；翻译与分类不追加此规则。新默认提示词同步说明要求，启动迁移同时识别 0.0.7 及以前、0.0.8 的准确默认文本，只替换未修改的默认值。自定义提示词、个人签名设置和已有草稿保留。

回复任务支持可选 `replyPreset`：`interested`、`decline`、`thanks`，对应感兴趣回复、不感兴趣回复和感谢回复。态度说明位于共用的 [ReplyPresets.json](../Sources/BoxmailCore/Resources/ReplyPresets.json)，追加到用户自定义回复提示词之后；`prompt` 继续传入补充要求。未知态度会在模型调用前拒绝。

客户端发送 `task: "reply"`、`messageId`、`preview: true`，任务保留 `replyPreset`、`preview`，结果只含 `subject` 和 `body`，不会创建草稿。用户选择使用内容后，`POST /jobs/:id/draft` 创建草稿并回写 `result.draftId`，保存原邮件关联和回复线程。后续重复使用保留编辑；草稿删除或已进入发送流程时返回 `409`，原邮件缺失返回 `404`。旧客户端不传 `preview: true` 时仍直接生成待审核草稿。生成失败会保留此前成功的预览。

JPEG、PNG、GIF、WebP 通过 [Files API](https://api-docs.deepseek.com/zh-cn/api/create-file/) 以 `purpose=user_data` 上传，再通过 `input_image.file_id` 引用；上传设置一小时有效期，任务结束后尝试删除临时文件。PDF 使用已有 PDF 解析依赖转换页面为 PNG，无需 OCR 服务，每次最多 20 页，页面图片合计最多 25 MB；超限会提示拆分，不会静默遗漏页面。PPT / PPTX（含 PPS / PPSX）先通过 macOS Quick Look 生成本机预览，由随 App 签名打包的 `BoxmailPresentationRenderer` 使用 WebKit / PDFKit 生成每页独立的 PDF，再复用同一 PNG 转换和 Files 上传流程，最多 20 页、页面图片合计最多 25 MB。PPTX 临时副本展开隐藏页并校验页数；旧 PPT 使用系统预览可见页。转换支持取消、60 秒进程超时和临时目录清理，失败不覆盖已有分析。渲染关闭文档脚本和外部网络资源，不依赖 Office、LibreOffice 或在线转换服务。新附件提取文本用于搜索，旧 PPT 在重新理解成功后补齐文本。DOCX、XLSX 和文本附件提交提取内容，最多 60,000 字符，超过时在上下文中标明截断。

DeepSeek 目前只在 `deepseek-flash` 支持图片输入，选择 `deepseek-v4-pro` 解析图片会提示切换模型。其他服务商须同时支持此 Responses/Files 格式，实际兼容性需联调。


后台整理每批最多 6 封，使用主题、发件人及最多 600 字正文摘要；每批独立沿用设置中的超时与思考等级。任务保存 `messageIds`、`completedIds`、`progress`（`total`、`completed`、`failed`、`batchSize`、`batch`）及建议，不保存 API Key。重试只提交未完成 ID，忽略不属于当前批次的模型输出。`needsApproval`、`partial` 和 `paused` 状态中已有的建议可确认应用，应用后可撤销；`running` 状态不可应用。旧版失败任务没有批次信息，应重新开始整理。

翻译结果写入所属邮件的 `translation`，同步和跨文件夹移动保留译文。客户端的附件任务同时传入 `messageId`、`attachmentId`，后端校验归属；任务保存两者关联，并把所属邮件主题、发件人及最多 5,000 字正文加入附件理解上下文。

SQLite 使用 WAL 模式，当前 `user_version` 为 `2`。首次升级会在 `backups/` 写入一致性数据库备份，再以事务创建邮件账号日期和远端 UID 查询索引；不会每次启动重置结构版本，较新版本数据库会拒绝打开。`records` 表按 `kind` 和 `id` 保存 JSON，`events` 表保存活动记录；附件文件存入数据目录的 `attachments/`。应用版本与数据库结构版本分别管理，后续结构变化需要补充迁移逻辑。

后端不会把邮箱密码或 API Key 保存到数据库；客户端从钥匙串读取后，在任务请求中传入。邮件缓存和附件为本机明文数据，文件访问权限不能替代加密。

账号安全连接沿用 `imapTLS` 和 `smtpTLS` 字段以兼容已配置账户：`true` 表示 SSL/TLS 直连，`false` 表示必须升级 STARTTLS。IMAP 和 SMTP 均启用服务器证书验证，账号 ID 和钥匙串凭证键保持不变。

连接测试分别验证 IMAP 和 SMTP，某一项失败时仍返回另一项的结果。认证失败会标明协议和服务器状态码；同步登录错误也使用相同说明。错误响应不包含授权码、认证载荷或原始服务器返回。

邮件记录同时保留纯文本 `body` 和已清理的 `html`，以 `bodyVersion: 1` 标记新版正文缓存。Mailparser 将 CID 图片转为本机 Data URL；HTML 仅保留阅读所需标签、属性和样式。同步发现旧缓存时重新读取邮件源，只补正文字段，不重建附件、不覆盖摘要或分类；完成后继续复用缓存。客户端启动发现旧正文缓存会执行一次同步，纯文本仍用于搜索、复制及 AI 上下文。

## 联调时需要保留的行为

同一账户不能并发同步；单封 AI 任务串行，同一账户最多一个后台整理任务，整理期间仍可使用单封 AI 功能，冲突请求返回 `409`。已读、星标及文件夹更改先记录本机操作，再于同步时提交；AI 分类只更新本机标签。邮件和附件内容作为模型输入，不作为后端可执行指令。

发送必须显式确认。草稿状态包括 `draft`、`sending`、`sent` 和 `uncertain`：发送成功后重复请求不会再次发送，结果不明确的草稿禁止自动重试。启动时把中断的发送标为 `uncertain`，把中断的单封 AI 任务标为失败，后台整理任务标为 `paused` 并保留建议和已完成 ID。SMTP 接受后归档失败会返回提示，不能据此再次发送。

历史同步采用可恢复的分批回填，每个文件夹每次最多下载 200 封，后续同步继续。每轮完整元数据校准用于识别旧邮件的状态和删除变化，暂未采用 IDLE 或 CONDSTORE 优化。服务器草稿同步尚未实现；Gmail、Outlook 专用接入及 OAuth 已排除在当前开发计划之外。真实服务验证和版本提交流程见 [开发文档](../docs/DEVELOPMENT.md)。

## 0.0.6 接口补充

- `GET /state?compact=1`：保留用于总览、计数和附件导航的轻量邮件索引；不返回邮件正文、HTML、译文、附件提取文本或附件理解全文。兼容旧客户端的 `/state` 仍返回完整数据。
- `GET /messages?accountId=...&folder=inbox&filter=...&q=...&limit=100&offset=0`：分页列表、总数及 `nextOffset`；limit 为 1 至 200。关键词搜索仍为 SQLite 子串查询，尚未接入 FTS。
- `GET /messages/:id`：完整邮件和 `bodyLoaded: true`。
- `POST /messages/:id/reply-draft`：`all`、`forward`，根据所属账户生成并保存草稿；处理 Reply-To、原 To/Cc、自身地址排除、去重与 References。
- `POST /sync`：新增 `background: true` 和可选 `folder`，立即返回后台任务受理结果；不传 background 时保留等待完成行为。邮箱凭证仅在任务运行期间使用。
- `GET /sync-status`：运行中的账号、各文件夹进度及本次运行结果；进度存入 `sync` 记录，关闭中断会转为可继续状态。
- `GET /attachments/:id/metadata`：按需读取文本和理解结果。
- `GET /attachments/:id/preview`：XLSX 原格式 HTML，本机生成，不执行脚本、加载远程资源或计算公式。其余格式由原生客户端预览原文件。

收信保存 Reply-To、In-Reply-To 和 References。UIDVALIDITY 变化或检测到远端移动时，原本机附加信息会存入 `recovery` 记录；仅在同账号的 Message-ID 可唯一匹配时重新关联，歧义记录保留待恢复。发送继续使用明确确认和结果不确定时禁止自动重试的机制。

附件中心使用 `GET /attachments/search?accountId=...&q=...` 查询完整提取文本和理解结果，只返回匹配 ID；轻量附件记录仅包含各 160 字符的预览片段，避免把完整附件文本装入列表。

## 0.0.12 恢复、取消归档与清空

邮件记录保存 `deletedFromFolder` / `deletedFromPath` 和 `archivedFromFolder` / `archivedFromPath`，在移动前记录来源，后续同步、UID 变化和“归档 → 删除 → 恢复”继续保留。状态、分页列表和详情额外返回可选的 `restoreFolder`、`unarchiveFolder`，供客户端展示实际目标。来源缺失时先解析旧服务器路径，再按账户地址识别已发送，其余回到收件箱。相同 Message-ID 的收件和已发送副本优先使用目标 UID 与 UIDVALIDITY 关联，避免串用来源。

恢复与取消归档先更新本机并登记移动，下次同步提交远端；同步前撤回移动会跳过同文件夹操作。`POST /trash/empty` 要求明确确认，真实账户需运行时 IMAP 凭证；先执行待处理恢复，再清空整个服务器 Trash，包括未缓存邮件。成功后清理当前账户本机记录与无引用附件，仍被其他邮件、草稿或恢复记录使用的附件保留。同步、清空及冲突的 AI / 账户操作通过现有账户互斥检查；拒绝或失败时返回具体错误。演示账户仅操作本机。

缓存统计继续使用同一份本机邮件索引，当前文件夹数与全部账户合计按各自范围展示；服务器同步快照独立显示。此版只增加记录字段，不改变 SQLite `user_version=2`。实现与验收见 [0.0.12 发布说明](../docs/V0_0_12.md)。

## 0.0.11 模型列表缓存

`GET /ai/models?baseURL=...` 和 `POST /ai/models` 均返回 `{models: [模型名称]}`。GET 只读取本机，未缓存时返回空数组；POST 调用服务商 `/models`，要求响应 `data` 为包含有效字符串 `id` 的数组。名称移除首尾空白并去重，成功后替换完整列表，合法空数组清空列表；HTTP 失败、无效 JSON 或无效条目不修改旧缓存。

记录以 `modelCatalog` 类型保存在 `records` 表中，ID 为 `aiConfig` 校验和规范化后的 API 基地址，内容只含 `id`、`models` 和 `updatedAt`。本次不改变数据库结构版本。缓存独立于 `/settings` 保存，随数据库关闭和重启保留，并随本机数据目录迁移；不存储请求中的 API Key。前端读取缓存时检查当前地址与刷新代次，避免旧请求覆盖新列表或其他服务的选项。


## 0.0.7 本封邮件附件批量理解

- `POST /messages/:id/attachments/analyze`：传入当前 `accountId` 与运行时 `apiKey`，立即返回后台 `attachmentBatch` 任务。默认处理本封邮件全部未理解附件，`force: true` 明确重新处理全部。重复提交同一邮件返回现有运行任务，客户端不需逐个选文件。模型地址、提示词与超时使用已保存设置。
- `GET /jobs/:id`：`attachmentItems` 按邮件附件顺序返回 `id`、`name`、`status` 与 `error`。单项状态为 `pending`、`running`、`completed`、`existing`、`failed`、`unsupported`；`progress.completed` 包含已有结果复用项。
- `POST /jobs/:id/pause`：中断当前请求，保留已保存结果。`POST /jobs/:id/retry` 携带运行时 `apiKey`，仅继续失败或未完成附件，已完成与不支持项不重复请求。应用重启把未完成批量任务恢复为暂停。

每封邮件依序处理附件，每个请求独立使用配置超时和所属邮件上下文；某项失败后继续后续项。结果必须完整且非空才写入附件，失败不覆盖原有理解结果。重试原任务不会纳入后来新增的附件；新建批量任务会重新确定当前附件范围。不支持的格式可预览、下载。API Key 不写入任务记录；附件所属邮件及账户在入队和执行前均检查，运行期间禁止移除该账户或同时单独重写同封附件。


## 0.0.8 精简总结与下一步建议

总结响应新增 `overview` 和 `nextSteps`，保留兼容的 `points`、`todos`、`keyInfo`。新响应可以只提供有效 `overview`；后端补齐兼容字段。旧模型响应仍可仅提供非空 `points`，无效或空白摘要不会覆盖已有总结。

`nextSteps` 每项为 `{title, action, prompt}`，最多保存 4 项。支持 `reply`、`attachments`、`note`：仅带起草要求的 `reply` 可衔接回复预览，仅有本封附件时支持 `attachments`，其他值降为文字提醒。总结生成本身不执行建议；用户点击后才请求相应操作，回复仍先预览、使用后创建草稿、发送前确认。模型不能通过建议引入发送、删除等任意操作。

`DefaultPrompts.json` 更新总结及附件理解默认提示词。启动时只替换与 0.0.7 及以前默认值完全相同的配置，保留自定义内容、模型地址、超时与其他设置。已生成的总结不自动重写，重新生成时使用当前提示词。
