# 本机后端与 API

后端使用 Node.js 24、内置 SQLite 和锁定的 npm 依赖，由 macOS 客户端作为子进程管理，负责邮件协议、AI、附件、搜索与数据维护。当前版本见根目录 [VERSION](../VERSION)，开发流程见 [开发说明](../docs/DEVELOPMENT.md)，用户行为及容量限制见 [使用指南](../docs/USER_GUIDE.md)。

## 独立启动

从 `Backend/` 执行以下命令，使用独立数据目录，不与正在运行的 App 共用：

```bash
npm ci
export BOXMAIL_DATA="${TMPDIR:-/tmp}/boxmail-dev"
export BOXMAIL_TOKEN="$(node -e "process.stdout.write(require('node:crypto').randomBytes(32).toString('hex'))")"
export BOXMAIL_PORT=56123
export BOXMAIL_DEMO=1
npm start
```

服务启动后输出端口，按 Ctrl+C 关闭，联调数据保留。完整回归从仓库根目录执行 `./script/test.sh`；直接 `npm test` 在缺少原生渲染组件时会跳过 PPT 渲染测试。合成样例及依赖说明统一见开发说明。

| 环境变量 | 用途 |
| --- | --- |
| `BOXMAIL_DATA` | 必填，数据库和附件目录 |
| `BOXMAIL_TOKEN` | 必填，至少 24 字符的会话令牌；客户端每次启动生成 |
| `BOXMAIL_PORT` | 监听端口，省略或为 0 时由系统分配 |
| `BOXMAIL_DEMO` | 默认初始化演示数据，设为 0 关闭 |
| `BOXMAIL_PRESENTATION_RENDERER` | 独立联调时指定 PPT 原生组件路径；App 使用内置组件 |

服务仅监听 `127.0.0.1`。每个请求携带 `X-Boxmail-Token`，带 `Origin` 的请求拒绝访问。请求体为 JSON 对象，上限 40 MB；成功返回 JSON，错误返回 `{"error":"错误说明"}` 和 HTTP 状态码，附件字节以 Base64 返回。

## HTTP 接口

### 邮件、账户与附件

| 方法 | 路径 | 参数与行为 |
| --- | --- | --- |
| GET | `/state` | 完整状态；`compact=1` 返回轻量邮件索引，不带正文及完整附件文本 |
| GET | `/messages` | `accountId`、`folder`、`filter`、`q`、`limit`、`offset`；默认每页 100，limit 1 至 200，返回总数与 nextOffset |
| GET | `/messages/:id` | 完整邮件及 `bodyLoaded: true`，也支持草稿搜索结果 |
| GET | `/messages/:id/thread` | 同账户引用链、原邮件头、总数、分页及未缓存提示 |
| POST | `/messages/:id/reply-draft` | `all`、`forward`，按原账户生成草稿和引用头 |
| PATCH | `/messages/:id` | 更新 `unread`、`starred`、`folder` 或本机 `category` |
| POST | `/messages/:id/restore`、`/messages/:id/unarchive` | 返回删除或归档前的文件夹 |
| POST | `/trash/empty` | `accountId`、`password`、`approved: true`；清空整个服务器及本机 Trash |
| POST | `/accounts/test` | `account`、`password`；分别测试 IMAP / SMTP |
| POST / DELETE | `/accounts`、`/accounts/:id` | 保存账号配置 / 移除本机账号及缓存，保留服务器邮件 |
| POST | `/sync` | `accountId`、`password`；可选 `background: true` 和 `folder`，后台模式立即返回 |
| GET | `/sync-status` | 运行账号、文件夹进度及本次结果 |
| POST / DELETE | `/drafts`、`/drafts/:id` | 保存 / 删除本机草稿 |
| POST | `/send` | `draftId`、`password`、`approved: true`；显式确认发送；同一草稿并发只投递一次，重复请求返回 409 |
| POST | `/attachments` | `name`、Base64 `content`，可带关联 ID 和 `contentType` |
| GET | `/attachments/:id` | 名称及 Base64 原始字节 |
| GET | `/attachments/:id/metadata` | 按需读取提取文本和理解结果 |
| GET | `/attachments/:id/preview` | 本机生成的 XLSX 静态 HTML；其他格式由客户端预览 |
| GET | `/attachments/search` | `accountId`、`q`；在完整附件文本和分析中搜索，返回匹配 ID |

### 搜索、配置与维护

| 方法 | 路径 | 参数与行为 |
| --- | --- | --- |
| GET | `/search` | `q`、可选 `accountId`；邮件及附件搜索 |
| GET | `/search/parse` | `q`；解析查询或返回具体错误 |
| GET / POST | `/search/index`、`/search/rebuild` | 查看索引状态 / 无活动任务时重建 |
| GET | `/contacts` | `accountId`、`q`；当前账户历史及草稿联系人 |
| GET / POST | `/categories` | 读取目录 / 新增 `name` 和可选 `description` |
| PATCH / DELETE | `/categories/:id` | 修改名称及说明 / 删除并将相关邮件归为未分类 |
| POST | `/settings` | `ai`、`preferences`；保留已有凭证引用和独立模型缓存 |
| POST | `/configuration/export` | 返回真实账号、AI 和偏好，不含密钥、本机凭证引用或邮件数据 |
| POST | `/configuration/inspect` | `configuration`；返回合并映射及当前修订值 |
| POST | `/configuration/import` | 配置、账号映射、修订值、凭证引用及 `approved: true`；事务提交并返回账号与设置 |
| POST | `/backups/create` | 本机绝对 `path`；生成并复核 ZIP |
| POST | `/backups/inspect` | `path`；校验并返回摘要和 SHA-256 |
| POST | `/backups/restore` | `path`、检查得到的 `sha256`、`approved: true`；恢复前保存完整备份 |

### AI 与任务

| 方法 | 路径 | 参数与行为 |
| --- | --- | --- |
| POST | `/ai/test` | `config`、`apiKey`；实际请求模型，可能产生费用 |
| GET | `/ai/models` | 可选 `baseURL`；只读取本机列表缓存 |
| POST | `/ai/models` | `config`、`apiKey`；刷新服务商列表，成功后替换缓存 |
| POST | `/agent` | `task`、`apiKey` 及任务参数；单封任务返回结果，classify 兼容后台整理 |
| POST | `/organize` | `accountId`、`apiKey`、`scope`（unclassified / inbox）、`limit`（1 至 200）；立即返回后台任务 |
| POST | `/messages/:id/attachments/analyze` | `accountId`、`apiKey`；批量处理，`force: true` 重新理解全部 |
| GET | `/jobs/:id` | 任务及批次进度 |
| POST | `/jobs/:id/draft` | 回复预览转草稿，重复使用保留编辑 |
| POST | `/jobs/:id/pause`、`/jobs/:id/retry` | 中断 / 仅继续未完成项，重试传运行时 `apiKey` |
| POST | `/jobs/:id/approve`、`/jobs/:id/undo` | 确认 / 撤销分类 |
| POST | `/todos` | `messageId`、`todoId`、`done`；更新摘要待办 |

字段以 [Swift 模型](../Sources/BoxmailCore/Models.swift)、[客户端状态与调用](../Sources/Boxmail/Stores/MailStore.swift) 和 [server.js](src/server.js) 为准。新增字段需同步两端及相关契约测试。

## 数据与同步契约

`database.js` 在 WAL 模式保存 `records(kind, id, JSON)` 和活动 `events`，结构版本为 2。迁移前在数据目录 `backups/` 保存一致性数据库备份，不重置较新版本数据库。外置附件放在 `attachments/`，迁移位置由客户端在服务启动前完成，双方共同持有数据目录锁。

密钥由客户端从钥匙串读取并在任务请求中传入，不写入 SQLite、任务或模型缓存。`settings.credentialReferences` 只保存本机钥匙串引用，普通设置保存和重启保留；导出移除引用，导入按邮箱合并，客户端先写新凭证，再事务切换账号、设置和引用。修订冲突及提交失败保持旧配置。

每个文件夹同步先完整校准 UID 和标志，再下载最多 200 封缺失或需修复正文，逐封持久化 `sync` 进度；元数据读取不完整时不据此删除缓存。UIDVALIDITY 变化取消旧待提交操作，本机附加信息放入 `recovery`，只按同账户唯一 Message-ID 恢复，歧义记录保留。同步结束以最新账户记录为基准合并 `folders` 与 `lastSync`，同步期间保存的账号设置不被覆盖。

`imapTLS` / `smtpTLS` 的 true 表示 SSL/TLS 直连，false 表示必须 STARTTLS，均验证证书。连接测试分别报告协议结果，错误不回显凭证或原始认证数据。邮件保留 Reply-To、In-Reply-To、References；`bodyVersion: 1` 标记清理后的 HTML / CID 正文，旧缓存修复保留附件、摘要和标签。

删除与归档来源保存在 `deletedFromFolder/Path`、`archivedFromFolder/Path`，接口返回可选 `restoreFolder`、`unarchiveFolder`。恢复先更新本机并登记远端移动，清空先提交待处理恢复，再清理整个服务器 Trash；失败保留本机记录，其他邮件、草稿及 recovery 引用的附件保留。

全文搜索通过 SQLite 触发器登记 message / attachment / job 变化，检索时增量补齐双字符 n-gram 索引并核对子串，单字符回退。`q` 支持关键词、短语及 from / to / cc / subject / category / after / before / is / has / account / folder，参数绑定不执行原始查询。明确 `folder:drafts` 时查询未发送本机草稿，ID 带 `draft:` 前缀及 `draftId`，日期取最后更新时间，不增加普通邮件索引数。

会话按同账户引用链归并，联系人只来自当前账户，分类目录及任务快照保存在 records。模型列表以规范化 API 地址作为 `modelCatalog` ID，只保存 models 和 updatedAt；成功刷新替换、合法空数组清空、失败保留，独立于设置应用与取消。

备份为 SQLite 快照、附件及逐项 SHA-256 清单。恢复核验路径、未知文件、完整性、必要字段和引用，恢复前备份失败即停止；事务失败回滚并清理暂存，成功后重建派生索引。维护期拒绝并发写入，容量边界见使用指南。

## AI 请求与任务恢复

`responses.js` 发送 `instructions`、`input`、`reasoning.effort` 和 JSON 输出格式，使用 SSE `stream: true`，兼容普通 JSON 响应。只读取完成的 assistant `output_text`，忽略思考内容；不发送温度或 token 上限。断流、无效或不完整结果不覆盖原结果。

单封总结、回复和翻译携带每份附件的名称、最多 16,000 字符提取文本和 16,000 字符已有分析，截取单独标明，整体保持有效 JSON。附件分析校验邮件归属，附带主题、发件人及最多 5,000 字正文。

默认配置和精确升级逻辑位于 `ai-settings.js`，共享资源为 [DefaultPrompts.json](../Sources/BoxmailCore/Resources/DefaultPrompts.json) 及 [ReplyPresets.json](../Sources/BoxmailCore/Resources/ReplyPresets.json)。运行时对撰写任务追加无签名要求，翻译与分类不追加；未知回复态度在调用前拒绝。

回复用 `task: "reply"`、`messageId`、`preview: true` 生成仅含 subject / body 的预览。显式使用后创建并关联草稿；草稿删除或进入发送流程返回 409，原邮件缺失返回 404。旧客户端省略 preview 时保留直接生成待审核草稿的兼容行为。

总结兼容 overview / nextSteps 与 points / todos / keyInfo。最多 4 项 nextSteps，只允许 reply / attachments / note；无效动作降为文字提醒，生成总结本身不执行建议。

整理每批最多 6 封，正文摘要最多 600 字，逐批保存 completedIds 和 progress，重试只提交未完成 ID。分类在 needsApproval / partial / paused 时可确认，running 时不可应用，应用后可撤销。

附件批量任务按邮件顺序保存 attachmentItems，状态为 pending / running / completed / existing / failed / unsupported。重复点击复用运行任务，重试保留原范围，新增任务才纳入新附件；入队和执行前检查所属邮件及账户，失败继续后续文件并保留旧分析。

图片通过 Files 上传，以 `input_image.file_id` 引用，设置一小时过期并在结束后尝试删除。PDF 逐页转 PNG，PPT 经 `presentations.js` 和原生组件转 PDF 后共用流程；PPTX 隐藏页在临时副本展开，原件不变，转换支持取消、60 秒子进程超时及清理。限制与预览差异统一见使用指南。

同账户同步互斥，单封 AI 串行，同账户最多一个整理任务。发送前在事务内认领草稿，同一草稿并发只投递一次、重复请求返回 409，投递前失败恢复为草稿；SMTP 接受后归档失败不能重发。收件人接受 RFC 5322 显示名形式（`姓名 <邮箱>`），仍拒绝控制字符与注入式分隔符。已发送副本接管归属草稿的附件，转发复用的原邮件附件保持原归属。启动时发送中草稿转 uncertain、单封 AI 转失败、整理与附件批量任务转 paused，并保留结果和进度。
