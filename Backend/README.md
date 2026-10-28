# 本机后端与 API

后端使用 Node.js 24、内置 SQLite 和锁定的 npm 依赖，由 macOS 客户端作为子进程管理，负责邮件协议、AI、附件、搜索与数据维护。0.1.3 与客户端同步版本，凭证继续由客户端从本机 `.env` 读取，沿用现有同步、AI、附件、搜索和恢复能力；HTTP 契约和数据库结构版本 2 保持兼容。当前版本见根目录 [VERSION](../VERSION)，开发流程见 [开发说明](../docs/DEVELOPMENT.md)，用户行为及容量限制见 [使用指南](../docs/USER_GUIDE.md)。

HTML 转发草稿使用可选的 forwardedHTML、forwardedText 成对保存原文，body 为可编辑转发说明；保存时校验并清理 HTML，旧草稿字段缺省兼容。发送同时生成 text/html 和 text/plain，将本机 data 图片改为 CID 内嵌资源，保留链接地址且不主动下载外部图片。本机已发送副本保留原 HTML，草稿预览和搜索包含转发原文。客户端的收件人标题与滚动条处理仅用于展示，不写回 forwardedHTML，也不改变发送内容。

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
| `BOXMAIL_PARENT_PID` | App 指定的父进程；退出或消失后关闭服务 |
| `BOXMAIL_LIFETIME_PIPE` | App 内部设为 1，通过 stdout 管道检测 App 消失，避免父 PID 被复用后留下服务；独立启动无需设置 |

`.env` 由桌面客户端直接解析，不自动载入后端进程环境；独立启动后端仍需在同步、发送和 AI 请求体中传入凭证。

服务仅监听 `127.0.0.1`。每个请求携带 `X-Boxmail-Token`，带 `Origin` 的请求拒绝访问。请求体为 JSON 对象，上限 40 MB；成功返回 JSON，错误返回 `{"error":"错误说明"}` 和 HTTP 状态码，附件字节以 Base64 返回。

## HTTP 接口

### 邮件、账户与附件

`POST /messages/batch` 的请求为 `{updates:[{id,changes,expected?}]}`。changes 只允许 folder、category、unread、starred；ID 不可重复。所有记录与账户锁先统一检查，字段校验及待同步操作在同一事务中提交。返回的 undo 项含原字段 changes 与操作后 expected，可原样再次提交进行撤销；只还原本次变化的字段，不覆盖其他编辑。任一 expected 不匹配或邮件身份已改变时返回 409，整批保持原状。每批最多 1000 项，仅对已缓存的邮件生效，不包含本机草稿。纯分类请求只修改本机标签，沿用现有单封接口的同步锁语义。

| 方法 | 路径 | 参数与行为 |
| --- | --- | --- |
| GET | `/health` | 经会话令牌认证的就绪检查，不读取全量邮件状态 |
| GET | `/state` | 完整状态；`compact=1` 返回轻量邮件索引，不带正文及完整附件文本；同时传 `previews=0` 时仅复用已有预览缓存，未生成项为空，由 `/messages` 分页补齐；summary / translate / attachment 任务省略重复 result |
| GET | `/messages` | `accountId`、`folder`、`filter`、`q`、`limit`、`offset`；默认每页 100，limit 1 至 200，返回总数与 nextOffset；`groupBy=sender` 按发件人分页，`senderGroup` 分页读取组内邮件 |
| GET | `/messages/:id` | 完整邮件及 `bodyLoaded: true`，也支持草稿搜索结果 |
| GET | `/messages/:id/thread` | 同账户引用链、原邮件头、总数、分页及未缓存提示 |
| POST | `/messages/:id/reply-draft` | `all`、`forward`，按原账户生成草稿和引用头 |
| PATCH | `/messages/:id` | 事务更新 `unread`、`starred`、`folder` 或本机 `category`；任一字段失败时整体回滚，包括待同步操作 |
| POST | `/messages/:id/restore`、`/messages/:id/unarchive` | 返回删除或归档前的文件夹 |
| POST | `/messages/batch` | 1 至 1000 项 updates；每项含 id、changes 及可选 expected，事务更新并返回 changedCount 和可撤销的 undo |
| POST | `/trash/empty` | `accountId`、`password`、`approved: true`；清空整个服务器及本机 Trash |
| POST | `/accounts/test` | `account`、`password`；分别测试 IMAP / SMTP |
| POST / DELETE | `/accounts`、`/accounts/:id` | 保存账号配置 / 移除本机账号及缓存，保留服务器邮件；发送中禁止移除，清理包含 recovery / relocation 附件并保留其他引用 |
| POST | `/sync` | `accountId`、`password`；可选 `background: true` 和 `folder`，后台立即返回并自动逐批补齐指定范围 |
| POST | `/sync/cancel` | `accountId`；停止该账户当前同步会话，保留已下载邮件与断点，重复停止可安全返回 |
| GET | `/sync-status` | 运行及排队账号、文件夹进度与阶段、本次结果；结果包含 queued / running / completed / paused / failed |
| POST / DELETE | `/drafts`、`/drafts/:id` | 保存 / 删除本机草稿；保存响应附签名过滤后的 `preview`；删除后清理未被邮件、其他草稿及保留记录引用的附件 |
| POST | `/send` | `draftId`、`password`、`approved: true`；显式确认发送；发送中或结果不明返回 409，已发送的重复请求返回 `alreadySent: true` |
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
| POST | `/settings` | `ai`、`preferences`；允许部分更新偏好，未提交字段保留；保留已有凭证引用和独立模型缓存 |
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
| GET | `/ai/models` | 可选 `baseURL`、`providerId`、`apiProtocol`；只读取本机列表缓存 |
| POST | `/ai/models` | `config`、`apiKey`；刷新服务商列表，成功后替换缓存 |
| POST | `/agent` | `task`、`apiKey` 及任务参数；可选 `background: true` 立即返回单封 Job，用 `/jobs/:id` 获取结果；缺省等待最终结果，classify 兼容后台整理 |
| POST | `/organize` | `accountId`、`apiKey`、`scope`（unclassified / inbox）、`limit`（1 至 200）；立即返回后台任务 |
| POST | `/messages/:id/attachments/analyze` | `accountId`、`apiKey`；批量处理，`force: true` 重新理解全部 |
| GET | `/jobs/:id` | 任务及批次进度 |
| POST | `/jobs/:id/draft` | 回复预览转草稿，重复使用保留编辑 |
| POST | `/jobs/:id/pause`、`/jobs/:id/retry` | 中断 / 仅继续未完成项，重试传运行时 `apiKey` |
| POST | `/jobs/:id/approve`、`/jobs/:id/undo` | 确认 / 撤销分类 |
| POST | `/todos` | `messageId`、`todoId`、`done`；更新摘要待办 |

字段以 [Swift 模型](../Sources/BoxmailCore/Models.swift)、[AI 配置](../Sources/BoxmailCore/AIConfig.swift)、[客户端状态与调用](../Sources/Boxmail/Stores/MailStore.swift) 和 [server.js](src/server.js) 为准。新增字段需同步两端及相关契约测试。

`GET /messages?groupBy=sender` 的 `messages` 仅包含各组的最新邮件，`senderGroups` 返回不透明的组 ID、accountId、规范化 senderEmail、latestMessageId、count、unreadCount；`total` 是匹配邮件数，`groupTotal` 是发件人数，`nextOffset` 按发件人计算。归组使用完整匹配结果的轻量元数据，只为当前页生成预览；地址忽略首尾空白和大小写，账户各自独立，空地址逐封保留。组间和组内按实际日期倒序，同一时刻按 ID 确定顺序。

展开时传入返回的 `senderGroup`，并保留原有 accountId、folder、filter、q，响应继续使用逐封 `messages/total/nextOffset`。`revealId` 让聚合页附带当前查询中指定邮件的组及 `revealedMessage`，不改变常规分页偏移；用于从摘要或附件定位第一页之外的邮件。草稿搜索保持逐封响应。HTTP、搜索和数据库结构版本保持兼容。

## 数据与同步契约

`database.js` 在 WAL 模式保存 `records(kind, id, JSON)` 和活动 `events`，结构版本为 2。迁移前在数据目录 `backups/` 保存一致性数据库备份，不重置较新版本数据库。外置附件放在 `attachments/`，迁移位置由客户端在服务启动前完成，双方共同持有数据目录锁。

同步新邮件时先准备附件文件，再在同一事务中登记附件与邮件；失败清理本次准备的文件，重试不会累积重复附件。恢复历史邮件时，附件归属、草稿和任务引用、恢复记录的移除与新邮件一并提交；事务失败保留原记录。独立添加附件的登记失败也会清理本次文件。事务中不执行异步文件或网络操作。

客户端启动使用 `compact=1&previews=0`，全局元数据不触发正文读取；列表页、邮件详情及会话当前页提供签名过滤预览。原 `compact=1` 契约保留。Word、表格及 AI SDK 在首次使用时加载，未发送草稿在 SQL 查询阶段筛选；已有格式化转发与普通回复不读取来源正文，完整旧转发仍按需恢复。

发送成功后，隐藏的草稿记录保留状态及防重复发送回执，正文、格式化转发快照和附件引用由已发送邮件持有。删除草稿、移除账户及明确清空已删除时共用附件引用检查；旧发送回执的附件引用不阻止清理，活跃草稿、邮件及 relocation / recovery 引用继续保留。备份要求 forwardedHTML / forwardedText 成对为字符串，字段均缺省的旧草稿继续兼容。

密钥由客户端从当前数据目录的 `.env`（或 `BOXMAIL_ENV_FILE` 指定文件）读取并在任务请求中传入，不写入 SQLite、任务或模型缓存。`settings.credentialReferences` 只保存本机凭证引用，对应 `.env` 的 `BOXMAIL_CONFIGURATION_<UUID>` 条目，普通设置保存和重启保留；导出移除引用，导入按邮箱合并，客户端先写新凭证，再事务切换账号、设置和引用。修订冲突及提交失败保持旧配置。

导入要求精确提供文件内邮箱与服务商的凭证引用：`default` 对应 `ai-key`，自定义连接对应 `ai-provider-<id>`；仅自定义连接时不要求 `ai-key`，旧版扁平 AI 配置仍使用默认引用。JSON 的 `credentials.aiKey` 保留旧格式兼容字段，未配置默认连接时导出为空且导入忽略；所有服务商的密钥由 Swift 客户端读写，不进入配置 HTTP 请求。提交响应丢失时客户端检查当前引用，确认已提交后保留密钥；无法确认时保留可能生效的凭证供重启恢复。

每个文件夹用 STATUS 与 UID SEARCH ALL 核对邮件数量，再按每页最多 200 个 UID 只读取 UID、FLAGS、RFC822.SIZE，避免批量 ENVELOPE / INTERNALDATE 被服务器截断。缺项按每批 50、10、1 个 UID 逐步补拉，每个原始页最多 24 次补拉，每条命令使用独立期限并支持取消。校验继续拒绝重复、非请求 UID、无效标志和大小；完整清单通过后才校准缓存，补拉后仍不完整则保留缓存，包括 UIDVALIDITY 已变化的旧缓存。EXAMINE 的缺失或误报计数不会直接当作空文件夹；服务器确认删除的邮件放入 `recovery`。服务商收取范围也会改变 IMAP 可见清单，客户端无法绕过，排查方法见使用指南。

`sync.inventory` 保留 selectedCount、statusCount、uidCount、metadataCount，并记录 metadataRequests（全部清单 FETCH 次数）、metadataRetryRequests（补拉次数）、metadataRecoveredCount（补拉成功的邮件数）、metadataMissingCount（当前页仍缺项的数量）及 metadataMissingUIDs（最多 20 个缺失 UID 样本）。进度、成功和失败均保存诊断；清单全部完成后缺项归零。普通邮件从单封正文读取时保留 INTERNALDATE，分段正文首段请求日期，缺项或 NO / BAD 响应重试时拆为单独正文请求；超过 25 MB 的邮件单独请求信封及日期，保留发件人、主题及时间，不下载超限正文。

`sync-session.js` 为一次 `/sync` 请求自动续跑批次；首先同步所选范围，再轮转未完成文件夹，健康文件夹继续补齐，清单或连接失败的文件夹保留错误。正文下载失败的邮件标识保存在本次会话的 deferredSources 中，后续批次跳过这些标识，避免同一封阻塞更旧历史；健康历史完成后，仅对只剩缺失正文的文件夹再执行一轮补拉，仍失败则 paused，下次新会话重新尝试。连续失败次数跨批次累计，连续三封正文失败时直接暂停该文件夹，避免大量连接重试。指定 folder 时不处理其他文件夹，账户保持互斥；无下载或修复进展时标记 paused 并保留未完成数量，避免空转。停止和服务关闭通过同一 AbortSignal 中断后续批次，已完成记录保留。

每个文件夹每批最多下载 200 封正文，并在约 20 秒预算后的下一封开始前让出；超过 1 MB 的 MIME 原文以 256 KB 分段读取，每次正文请求最多三次尝试，并核对响应 UID 与分段偏移。完整末段或 EOF 用于检查原文结尾；偏移错误、分段超量、缺项、大小不符或分段 NO / BAD 响应会回退完整 BODY.PEEK[]，替换此前所有分段，避免重复拼接或截断。单次 IMAP 读取限时 45 秒；待同步操作的文件夹选择、定位、标记、创建和移动也使用逐条 45 秒期限，并响应同步取消，失败时保留待同步记录。完整原文超过 25 MB 时拒绝缓存，已完成的邮件逐封保存。文件夹出错后关闭连接，重连并继续下一文件夹，最终汇总安全错误。客户端独立轮询进度，不等待所有启动响应；启动、查询与停止请求分别限时 10、8、5 秒。进度查询连续失败三次后请求停止并退出忙碌状态，内容刷新独立进行，每 12 秒至多发起一次，不阻塞进度。UIDVALIDITY 变化取消旧待提交操作，附加信息只按同账户唯一 Message-ID 恢复，歧义记录保留；标志无变化时跳过写入。同步结束以最新账户记录合并 `folders` 与 `lastSync`，保留期间保存的设置。

`sync.source` 保存累计 requests、retryRequests、fullFallbacks，以及最后的 lastUID、expectedBytes、receivedBytes 和安全 lastError；failedCount、failedUIDs（最多 20 个样本）、consecutiveFailures 和 deferredOnly 表示当前会话该文件夹的正文缺项。诊断不记录凭证、主题或正文，残缺原文不会标记为已下载；恢复连接后重新校验 UIDVALIDITY，身份变化时保留原缓存并停止该文件夹。

`imapTLS` / `smtpTLS` 的 true 表示 SSL/TLS 直连，false 表示必须 STARTTLS，均验证证书。连接测试分别报告协议结果，错误不回显凭证或原始认证数据。邮件保留 Reply-To、In-Reply-To、References；`bodyVersion: 1` 标记清理后的 HTML / CID 正文，旧缓存修复保留附件、摘要和标签。

删除与归档来源保存在 `deletedFromFolder/Path`、`archivedFromFolder/Path`，接口返回可选 `restoreFolder`、`unarchiveFolder`。恢复先更新本机并登记远端移动，清空先提交待处理恢复，再清理整个服务器 Trash；失败保留本机记录，其他邮件、草稿及 recovery 引用的附件保留。清空结束只将发现的文件夹合并到最新账户记录，保留期间保存的其他字段。

全文搜索通过 SQLite 触发器登记 message / attachment / job 变化，检索时增量补齐双字符 n-gram 索引并核对子串，单字符回退。完全相同的记录写入不触发更新，无变化同步不重写邮件；索引更新与重建在事务内完成，失败保留原索引及待更新标记。`q` 支持关键词、短语及 from / to / cc / subject / category / after / before / is / has / account / folder，参数绑定不执行原始查询。明确 `folder:drafts` 时查询未发送本机草稿，ID 带 `draft:` 前缀及 `draftId`，日期取最后更新时间，不增加普通邮件索引数。

会话按同账户引用链归并，分页前将当前邮件置顶，其余按时间倒序、相同时间按 ID 稳定排列；分页不重复当前邮件。联系人只来自当前账户，分类目录及任务快照保存在 records。模型列表按服务商 ID、协议和规范化 API 地址隔离，只保存模型 ID、服务商返回的名称及能力元数据和 updatedAt；原默认 Responses 连接沿用旧缓存 ID。成功刷新替换、合法空数组清空、失败保留，独立于设置应用与取消。Anthropic 模型列表按游标获取后一次提交，分页失败不覆盖旧缓存。

`mail-preview.js` 从完整缓存正文生成只排除签名的显示文本，保留引用历史。列表、紧凑快照、会话及草稿使用同一规则，HTML 只移除明确的签名容器，纯文本识别签名分隔符、企业联系信息及设备落款。Repository 按邮件 ID 在内存缓存短预览，实际邮件写入和删除使其失效，事务回滚或数据库句柄替换后清空。读取预览不重写邮件，不触发全文索引更新，也不要求重新同步。搜索仍匹配完整原文，正文片段在显示前按同一规则过滤；只有签名命中时回退到普通预览。完整正文与 HTML 不改动。

`/state` 的完整与轻量快照均为草稿附加 `preview`，与草稿搜索及保存响应共用规则；空字符串表示没有可显示的正文，客户端显示“尚未撰写正文”，不回退到含签名的 `body`。该字段按需生成，不写入数据库，也不采纳客户端提交的预览；`body` 继续用于编辑、保存和发送。

备份为 SQLite 快照、附件及逐项 SHA-256 清单。恢复核验路径、未知文件、完整性、必要字段和引用，恢复前备份失败即停止；事务失败回滚并清理暂存，成功后重建派生索引并清空邮件预览缓存，原 ID 被复用时也从恢复后的正文生成预览。维护期拒绝并发写入，容量边界见使用指南。

完整备份包含 `translationHTML`、`summaryHidden` 及完整总结、待办、服务商和模型参数。可选译文字段仅允许字符串或空值，收录字段仅允许布尔或空值；旧备份缺省值仍兼容。恢复会重定位附件路径，运行中的整理或附件批量任务暂停，单封 AI 任务失败、发送中草稿转为待确认；实时 AI 输出不持久化，客户端清空旧的显示、列表撤销和多选状态。

## AI 请求与任务恢复

`ai` 的 `providerId` 指定当前连接，`providers` 保存最多 20 个服务商，各项包括 id、name、baseURL、apiProtocol、model、models 和 catalogConfigured。Provider ID 以小写字母开头，仅含小写字母、数字和连字符；客户端逻辑凭证为 `ai-provider-<id>`，对应 `.env` 的 `BOXMAIL_AI_PROVIDER_<id>_KEY`；默认 `ai-key` 对应 `BOXMAIL_AI_KEY`，导入后按 `credentialReferences` 读取生成的条目。旧版平面配置自动作为默认连接，baseURL / model / apiProtocol 仍返回当前连接的镜像字段。模型 ID 可不在目录中，catalogConfigured 标记用户已配置目录，保留显式空目录。

`responses.js` 统一任务提示词、Files 附件生命周期与 JSON 结果校验。`ai-protocols.js` 使用 `@earendil-works/pi-ai@1.1.0` 的三个 lazy API 工厂及 `streamSimple`，由 pi-ai 调用 `openai@7.19.0`、`@anthropic-ai/sdk@0.129.0`；模型发现和 Files 上传、删除也使用同一版本的官方 SDK。依赖精确锁定并去重，不再维护自己的推理 HTTP 请求或 SSE 解析器。

| apiProtocol | 请求和完成条件 |
| --- | --- |
| `openai-responses` | `/responses`、Bearer 密钥、instructions / input / reasoning.effort / JSON 格式；以 completed 及 assistant output_text 为完成结果，原默认连接的图片通过 Files API，自定义连接由 pi-ai 内联 |
| `openai-completions` | `/chat/completions`、Bearer 密钥、system / user messages / JSON 格式；只接受 assistant 正文及 stop，图片通过 data URL |
| `anthropic-messages` | `/v1/messages`、x-api-key 和 anthropic-version；基础地址已含 `/v1` 时不重复添加；system / messages / 必需的 max_tokens，未配置时使用 32768 的能力回退值并按上下文可用量收缩，图片为 base64。流需 message_stop 及 end_turn / stop_sequence |

模型目录的 `models` 现为对象数组，兼容读取旧的模型 ID 字符串数组。每个模型支持以下字段，显示名称仅用于界面，实际请求始终使用 `id`：

| 字段 | 行为 |
| --- | --- |
| `id` / `name` | 必填且唯一的模型 ID、可选显示名称 |
| `contextWindow` | 输入与输出共用的上下文容量。未设置时回退 262144；使用 pi-ai 的 token 估算和上下文余量收缩输出容量，显式配置且输入估算已超出时在联网前拒绝。估算不等于服务商的精确分词 |
| `maxTokens` | 可选的单次输出上限，包含推理和回答。能力回退值 32768；OpenAI 未明确配置时不附加请求上限；明确配置后 Responses 发 `max_output_tokens`，Chat 发所选上限字段，Anthropic 发 `max_tokens` |
| `input` | `text`、`image` 的非空数组；未知自定义模型默认仅文本，不凭协议或模型名称推断视觉能力。文本模型收到图片时在上传前拒绝 |
| `reasoningEfforts` | `false` 关闭，或等级到发送值的字典；支持 off / minimal / low / medium / high / xhigh / max。只允许 off 的值为 null，表示不发送推理参数；启用时至少包含一个非 off 等级。模型菜单只提供已声明等级 |
| `compat.maxTokensField` | Chat Completions 的输出上限字段，默认 `max_completion_tokens`，可选 `max_tokens` |
| `compat.forceAdaptiveThinking` | Anthropic 为 true 时使用 `thinking: adaptive` 与 `output_config.effort` 映射值；否则使用 pi-ai 的预算模式，按等级分配思考 token 并为回答保留空间 |

客户端接受 K、M 容量输入，按十进制换算为正整数保存，1K = 1000。模型获取返回 `models` ID 数组及可选 `details` 元数据，供用户勾选加入目录；已有模型的自定义参数不会被刷新覆盖。旧默认 Responses 连接保留原有视觉及 Low / High / Max 配置，明确的逐模型声明优先。

三种协议均由 pi-ai 使用 SSE 请求并检查完整结束状态，只保存最终正文，忽略思考和工具内容。超时与调用者取消传给 SDK；`maxRetries: 0` 禁止一次操作隐式重试付费请求。客户端任务携带 providerId，服务端在调用前核对当前连接，不匹配返回 409；断流、无效或不完整结果不覆盖原结果。密钥只从本次调用传入，空密钥的本机服务不会读取 SDK 环境变量中的密钥或租户信息。

实现对照的参考版本为 DeepSeek Harness `687f282e8625c6b8d11ff58211a90524be2e4317`：表单参数见 [ModelRow](https://github.com/deepseek-ai/deepseek-harness/blob/687f282e8625c6b8d11ff58211a90524be2e4317/packages/client/ui-settings-models/src/client/ModelRow.tsx)、[容量编辑和校验](https://github.com/deepseek-ai/deepseek-harness/blob/687f282e8625c6b8d11ff58211a90524be2e4317/packages/client/ui-settings-models/src/client/DeepSeekModelsEditor.tsx) 和 [推理映射](https://github.com/deepseek-ai/deepseek-harness/blob/687f282e8625c6b8d11ff58211a90524be2e4317/packages/client/ui-settings-models/src/client/ModelReasoningEfforts.tsx)；运行链路见 [provider.ts](https://github.com/deepseek-ai/deepseek-harness/blob/687f282e8625c6b8d11ff58211a90524be2e4317/packages/llm/llm-pi-ai/src/provider.ts)、[catalog.ts](https://github.com/deepseek-ai/deepseek-harness/blob/687f282e8625c6b8d11ff58211a90524be2e4317/packages/llm/llm-pi-ai/src/catalog.ts) 和 [adapter.ts](https://github.com/deepseek-ai/deepseek-harness/blob/687f282e8625c6b8d11ff58211a90524be2e4317/packages/llm/llm-pi-ai/src/adapter.ts)。协议语义另核对 [OpenAI SDK](https://developers.openai.com/api/docs/libraries) 和 [Anthropic 思考模式](https://platform.claude.com/docs/en/build-with-claude/extended-thinking)。

单封总结和回复携带每份附件的名称、最多 16,000 字符提取文本和 16,000 字符已有分析，截取单独标明，整体保持有效 JSON。附件分析校验邮件归属，附带主题、发件人及最多 5,000 字正文。

`GET /ai/events` 使用与其他接口相同的 `X-Boxmail-Token`，返回 SSE：连接时发送 `{type:"snapshot",outputs:[...]}`，随后发送 `{type:"update",output:{id,task,status,accountId,messageId,attachmentId,parentJobId,text,html?,stage?}}`。15 秒心跳维持连接；重连获取活动任务快照，慢消费者断开后重连，服务关闭清理所有订阅。单封 `/agent` 缺省返回最终 Job，`background:true` 立即返回运行中的 Job，随后 GET `/jobs/:id` 查询，不重复提交模型请求；后台任务沿用单封 AI 锁与独立超时，关闭服务时取消并保存可重试状态。未读邮件总结仍由客户端每次最多选择 10 封逐封执行，一封失败后继续下一封。API Key 只在内存中用于本次任务。三种协议的文本增量均转为可读预览，不转发推理、工具内容或 JSON 语法；中间结果只保存在内存，最终响应须通过完整性及任务校验后才能提交数据库。

翻译仅发送主题和 `{segments:[{id,text}]}`，要求同序同 ID 的逐段译文；缺段、重复或未知 ID 拒绝保存。HTML 经原邮件清理规则后按文字节点对齐，只更改文字并转义，不接受模型生成的 HTML；`pre/code/kbd/samp`、独立 URL 和邮箱保持原样。纯文本邮件保留换行及空行。结果保存为 `translation` 和可选 `translationHTML`；列表及紧凑快照省略这两个大字段，同步保留完整译文。既有纯文本译文兼容读取，客户端可重新翻译以恢复 HTML 排版。

默认配置和精确升级逻辑位于 `ai-settings.js`，共享资源为 [DefaultPrompts.json](../Sources/BoxmailCore/Resources/DefaultPrompts.json) 及 [ReplyPresets.json](../Sources/BoxmailCore/Resources/ReplyPresets.json)。运行时对撰写任务追加无签名要求，翻译与分类不追加；未知回复态度在调用前拒绝。

回复用 `task: "reply"`、`messageId`、`preview: true` 生成仅含 subject / body 的预览。显式使用后创建并关联草稿；草稿删除或进入发送流程返回 409，原邮件缺失返回 404。旧客户端省略 preview 时保留直接生成待审核草稿的兼容行为。

`POST /summaries/visibility` 接收 `{accountId,hidden,messageIds:[...]}`，或 `{accountId,hidden,all:true}`，返回实际变更的 `messageIds`。`hidden:true` 仅移出摘要总览，`false` 恢复；单项和多选校验全部 ID 归属及总结存在性，任一无效则整体拒绝。清空仅覆盖当前账户非 Trash 的已总结邮件，已移除项不重复计入撤销。仅持久化 `summaryHidden`，不修改总结、待办、原邮件内容或 IMAP mutation；缺省为收录，同步及完整备份保留此状态，重新生成总结重置为收录。待同步 `relocation/recovery` 原件同时保留收录标记。

总结兼容 overview / nextSteps 与 points / todos / keyInfo。最多 4 项 nextSteps，只允许 reply / attachments / note；无效动作降为文字提醒，生成总结本身不执行建议。

整理每批最多 6 封，正文摘要最多 600 字，逐批保存 completedIds 和 progress，重试只提交未完成 ID。分类在 needsApproval / partial / paused 时可确认，running 时不可应用，应用后可撤销。撤销在事务中检查本次实际修改的分类；后续手动修改导致冲突时返回 409，整批保留现状，未实际改变的分类不参与撤销。

附件批量任务按邮件顺序保存 attachmentItems，状态为 pending / running / completed / existing / failed / unsupported。重复点击复用运行任务，重试保留原范围，新增任务才纳入新附件；入队和执行前检查所属邮件及账户，失败继续后续文件并保留旧分析。

原默认 Responses 连接的图片继续通过 Files 上传，以 `input_image.file_id` 引用，设置一小时过期并在结束后尝试删除；自定义 Responses 连接与其他协议按 pi-ai 的内容格式内联发送图片，无需 Files API。PDF 逐页转 PNG，PPT 经 `presentations.js` 和原生组件转 PDF 后共用流程；PPTX 隐藏页在临时副本展开，原件不变，转换支持取消、60 秒子进程超时及清理。限制与预览差异统一见使用指南。

同账户同步互斥，单封 AI 串行，同账户最多一个整理任务。发送前在事务内认领草稿，同一草稿并发只投递一次、重复请求返回 409，投递前失败恢复为草稿；SMTP 接受后归档失败不能重发。收件人接受 RFC 5322 显示名形式（`姓名 <邮箱>`），仍拒绝控制字符与注入式分隔符。

同步清单使用不含正文、译文和总结的临时投影；删除恢复和状态写入仍读取并保留完整原件。服务器已发送邮件按账户及 Message-ID 的索引匹配本机副本。AI 流在拼接预览前以 100 ms 合并增量，结束后仍完整校验 JSON；Files 方式上传图片不额外生成未使用的 Base64 副本。

PDF 文本提取和 PDF / PPT 页面栅格化通过 `pdf-processing.js` 在独立子进程运行，沿用锁定的 PDF.js 5.4.296；图像通过进程 IPC 返回，并在子进程中将 Buffer 显式规范为 PDF.js 所需的 Uint8Array。每页编码后立即销毁画布，工作完成、取消或超过 60 秒后回收进程。20 页、1800 px 最长边及页面图片合计 25 MB 的范围保持不变，PPT 原生转换继续沿用自己的 60 秒期限。

发送前为转发等借用的附件复制独立 ID 和文件，并与草稿引用在同一事务保存；失败清理新副本，SMTP 明确拒绝后的重试复用已准备的副本。发送成功后附件归属已发送邮件，本机副本同时保留 In-Reply-To 和 References，可立即关联原会话。同步也会修复旧版共享附件，覆盖已缓存邮件和服务器关联，保留原件及其分析，重复同步不再复制。附件理解任务同步改用新 ID，失败任务可继续重试，运行中的批量任务会跟随新引用。原邮件和转发副本可以分别预览、理解和删除。

启动时发送中草稿转 uncertain、单封 AI 转失败、整理与附件批量任务转 paused，并保留结果和进度。

聚合列表与组内分页复用同一查询的一份轻量元数据快照，不缓存邮件正文。SQLite 写入（含直接 SQL 和恢复）、查询变化、事务回滚或数据库连接变化后失效，避免展开多个发件人时反复扫描和排序整箱邮件；首次查询仍需扫描匹配元数据。

`unicode.js` 处理字符串边界：摘要和提取文本截断不切开 UTF-16 代理对，记录写入与 HTTP / SSE 字符串值输出使用有效 Unicode。兼容旧记录中的孤立代理项，读取时仅将无法表示的字符替换为 U+FFFD，不删除原邮件、正文或附件；有效字符与二进制文件不变。

## 运行诊断与大批量同步

`sync-queue.js` 在后端统一限制最多两个账户并发，排队账户也持有账户互斥锁并支持取消。`runningAccounts` 包含排队账户，避免客户端把等待误判为完成；`results` 补充 phase、startedAt、lastProgressAt。任务连续 120 秒无阶段或进度写入时触发 SYNC_STALLED，取消共享信号并保留断点。无响应的单条 IMAP 命令仍有独立 45 秒期限。

`sync-session.js` 在同一次会话内复用文件夹清单和轻量缓存头，避免每下载 200 封就再次扫描全部历史；每批通过 STATUS 检查数量、UIDVALIDITY 和 UIDNEXT，任一变化时重建清单，能检测总数相同的删除后新增；服务器未提供 UIDNEXT 时最多复用 60 秒，下一次会话重新获取。复用清单不再次推断删除或覆盖远程标志。新清单的缓存校准按 200 封分块提交并让出事件循环，元数据页间也让出，允许进度和取消请求响应。

`mail-content-worker.js` 保留原调用接口，通过 `parser-process.js` 和 `parser-runner.js` 复用独立子进程处理 MIME、正文清理及同步附件提取。单项默认 60 秒，V8 old-space 预算 192 MB；完成后 RSS 达到上限一半（默认 256 MB）或已复用 500 项时，在下一项任务前回收并重建进程，避免旧附件驻留内存挤占下一封正文；`parser-owner-watch.js` 每 100 毫秒检查整个解析进程的 RSS，默认超过 512 MB 时终止进程组，也覆盖原生图像缓冲区。所有者失联时，独立管道守护逻辑即使遇到解析主循环阻塞也能清理进程。子进程不继承应用令牌、API 密钥和 Node 预加载环境。

附件解析失败保留原文件并继续同步，MIME 失败进入会话内有限延后重试。文件与记录沿用原有事务规则。诊断只记录解析格式、输入大小、耗时、退出信号和静态错误分类，不保存原始 stderr。客户端也分类后端致命输出，识别服务退出并清理旧运行状态，再次同步可重新连接当前数据目录；既有待迁移计划仍等到下次 App 启动。后端资源计数仅覆盖后端进程，不包含独立解析子进程。定位证据和限制见 [build 35 崩溃记录](../docs/diagnostics/2026-10-28-parser-crash.md)。

`diagnostics.js` 写入 `logs/backend.jsonl` 及两份轮转文件，每份约 1 MB，异步队列有上限。记录账户匿名标识、阶段和计数、经过归一化的 API 路由、错误类型、状态码和耗时；不记录查询参数、请求体、原始错误内容、凭证或邮件内容。模型调用和模型目录失败也记录诊断。每 30 秒保存 RSS、CPU 时间和事件循环延迟，进程退出时刷新待写记录。

客户端另存 `app.jsonl`，记录 API 超时、轮询错误、连接和子进程退出。解码错误补充阶段、脱敏结构字段及静态分类，不包含字段值或原始错误描述。`DiagnosticArchive` 直接读取允许的轮转日志并生成 ZIP，不通过后端接口；清单只保留版本、系统、匿名账户状态和计数，排除数据库、凭证、邮件、附件和文件扩展属性。设置中的开发者页负责选择位置与显示结果。
