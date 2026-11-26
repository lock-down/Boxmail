# 开发与维护

本文对应 Boxmail 0.1.12（build 51）的源码工作区。客户端、后端与打包入口见下文。操作见 [使用指南](USER_GUIDE.md)，接口见 [后端文档](../Backend/README.md)。

## 源码入口

| 目录或模块 | 职责 |
| --- | --- |
| `Sources/Boxmail/App/` | 应用、场景和命令 |
| `Sources/Boxmail/Views/` | 邮件、写信、搜索、附件和设置界面 |
| `Sources/Boxmail/Support/` | 设计系统、动效、滚动及原生预览桥接 |
| `Sources/Boxmail/Stores/MailStore.swift` 及扩展 | 状态、后端调用、分页、缓存、AI 输出流和任务轮询 |
| `Sources/Boxmail/Stores/PagedListStore.swift`、`FollowUpStore.swift`、`Views/ChecklistView.swift` | 共用分页状态机、清单刷新与到期事项定位 |
| `Sources/Boxmail/Support/SettingsActionState.swift`、`Views/SettingsActionFeedback.swift` | 设置动作进度、结果状态与统一反馈 |
| `Sources/Boxmail/Views/RecipientDetailsView.swift`、`RecipientAddressList.swift`、`Support/ScrollEventRouting.swift` | 邮件头与引用共用收件信息展示、原生滚动及指针命中 |
| `Sources/Boxmail/Support/ControlStyle.swift`、`Views/ActionButton.swift`、`IconButton.swift`、`SelectionButton.swift` | 共用控件尺寸、对称标签边界、圆角、主次外观、指针反馈、焦点与选中语义 |
| `Sources/Boxmail/Views/TableSortButton.swift`、`MailSourceButton.swift` | 紧凑排序标题、列内容对齐及长来源名称的省略 |
| `Sources/Boxmail/Views/CossMenu.swift`、`Support/CossMenuAnchor.swift`、`Support/CossPopover.swift` | 应用内菜单、选择项、浮层定位和键盘操作 |
| `Sources/Boxmail/Support/AppicaIcon.swift`、`Sources/Boxmail/Resources/AppicaIcon/` | 界面图标名称、渲染和随 App 打包的 SVG |
| `Sources/Boxmail/Views/WorkspaceList.swift`、`ListPagination.swift` | 共用列表滚动边界、行反馈与分页栏 |
| `Sources/Boxmail/Stores/RuleWorkspaceStore.swift`、`SendQueueStore.swift`、`WritingPreferencesStore.swift` | 规则与用量、发送计划及写作偏好 |
| `Sources/BoxmailCore/MailQuery.swift`、`WorkspaceModels.swift`、`MailTimestamp.swift` | 共用查询定义、新工作区数据契约及含毫秒的 ISO 8601 时间解析 |
| `Sources/Boxmail/Views/CalendarMonthView.swift`、`DateTimeSelection.swift`、`Support/TextSubmitShortcut.swift` | 共用月历、日期时间选择及编辑器发送快捷键语义 |
| `Sources/Boxmail/Views/AnalysisDocumentView.swift`、`AnalysisTableView.swift`、`AnalysisCodeBlockView.swift`、`Support/AITextStyle.swift` | AI Markdown 正文、表格、代码和行内排版 |
| `Sources/Boxmail/Services/NotificationCoordinator.swift` | 系统通知权限、投递、来源定位与 Dock 角标 |
| `Sources/Boxmail/Views/ComposerWritingPopover.swift`、`WritingPreferencesView.swift`、`MailHistoryView.swift`、`ActivityView.swift` | 写作浮层、风格编辑、历史来源与活动记录 |
| `Sources/Boxmail/Support/WorkspaceSheetLayout.swift`、`AttachmentListLayout.swift` | 主窗口及嵌套弹窗的尺寸边界、附件表格的列宽与窄窗口断点 |
| `Sources/Boxmail/Support/WindowTitlebarRegion.swift`、`MainWindowLayout.swift` | 主窗口标题区域交互、原生缩放及默认／最小尺寸 |
| `Sources/Boxmail/Services/` | 后端生命周期、本机凭证和配置迁移 |
| `Sources/BoxmailCore/` | 数据模型、配置归档、存储迁移、后端进程与目录锁、文本与日期逻辑 |
| `Sources/BoxmailCore/Resources/` | 双端附件类型、诊断词表、提示词、回复态度、正文脚本及品牌图片 |
| `Tests/`、`Backend/test/`（本地，不跟踪） | Swift 与后端回归、合成样例 |
| `Backend/src/mail-translation.js`、`mail-organization.js`、`writing-preview.js`、`mail-history.js` | 翻译缓存、整理授权和试用、写作范围和来源校验、历史结果 |
| `Backend/src/mail-ai-context.js`、`attachment-text.js` | 兼容路径的整封上下文与文件提取 |
| `Backend/src/application-services.js`、`account-sync-coordinator.js`、`local-credentials.js` | 长驻服务组装、统一同步协调与执行时读取凭证 |
| `Backend/src/follow-ups.js`、`mail-rules.js`、`send-queue.js`、`mail-assistant.js`、`mail-query.js` | 独立领域记录、动作及查询；不借用 AI Job 表示生命周期 |
| `Backend/src/ai-instructions.js`、`ai-usage.js`、`realtime-mail.js`、`mail-source-references.js` | 任务指令与输出结构、实际用量、IDLE 监听及来源身份迁移 |
| `Sources/BoxmailPresentationRenderer/` | WebKit / PDFKit 幻灯片页面生成 |
| `Backend/src/` | 协议、HTTP、任务、持久化、索引及备份 |

修改接口时同步检查 Swift 模型、后端路由和调用方；修改数据结构需设计迁移和旧数据兼容。应用版本与 SQLite 结构版本独立，当前 `user_version=2`，搜索索引为可重建派生数据。

后端 AI SDK 精确锁定为 `@earendil-works/pi-ai@1.3.0`，其内部 `pi-telemetry` 同为 1.3.0；共用 `openai@7.19.0` 和 `@anthropic-ai/sdk@0.129.0`。升级依赖时同步提交 `Backend/package.json` 和 `Backend/package-lock.json`，已有检出在更新后执行 `npm ci --prefix Backend`。协议与模型参数约定见 [后端接口](../Backend/README.md#ai-请求与任务恢复)。

## 构建与测试

在仓库根目录执行，依赖及工具链要求见 README。普通源码检出可以直接构建：

```bash
swift build
git diff --check
```

`Tests/` 与 `Backend/test/` 及其样例仅保留在本地，不进入 Git。`Package.swift` 只在对应本地目录存在时声明 Swift 测试目标；新检出不含测试仍能构建 App。准备好三个本地测试目录后执行 `./script/test.sh`，缺少任一目录时脚本明确退出，避免把未执行回归当作通过。

构建、测试和后端启动均要求 Node.js 24.22.2 LTS 或更新的 LTS 版本，最低版本以 `Backend/package.json` 的 `engines.node` 为准，`Backend/src/check-node.js` 同时检查版本下限和 LTS 标记。构建在关闭 App 前完成检查，并按二进制内容更新内置 Node.js，避免文件时间导致旧运行时被保留。

`test.sh` 检查运行时后构建 `BoxmailPresentationRenderer`，通过 `BOXMAIL_PRESENTATION_RENDERER` 传给后端测试，再运行 Node.js 和 Swift 测试。工具链提供 `TestingMacros` 插件时显式加载，避免部分 Command Line Tools 未自动加载宏的问题。

当前源码回归覆盖 ZIP 与备份损坏缓存恢复、草稿异常和并发对账、附件及分类邮件分页、后台预览清理、富文本连续编辑、窗口原生缩放与默认还原，以及控件对齐、附件表格与面板适配。回归也覆盖统一查询、多标签、清单、自动整理授权、发送队列、历史结果与来源迁移、兼容路由、写作快捷键及输入法。各版本的验证范围与结果见 [变更记录](../CHANGELOG.md)。新增回归不得替换同名旧测试。

真实 HTTP/SQLite/Swift 回归包含六账户、12,001 封合成邮件及 4,135 个附件的加载、正文与 HTML 保留、设置保存和同目录重启。HTTP 夹具按会话隔离，正式测试继续覆盖凭证文件权限、手工修改、迁移、ZIP 排除密钥、WAL 强制退出、磁盘容量不足、事务回滚、网络期限与取消、JSON 主线程隔离及客户端旧响应竞态。大邮箱用例一次补齐 12073 封收件箱与 543 封已发送；AppKit/WebKit 用例检查定位、选择、分页、收件人滚动和转发预览。搜索派生索引在后台逐封处理，测试等待索引就绪，搜索请求本身不能触发全量 flush。发布时另验证正式包的图标、资源、源码、签名、首次启动及退出清理。

| 需要验证的范围 | 命令 |
| --- | --- |
| 完整回归 | `./script/test.sh` |
| 正文同步与大邮箱回归 | `cd Backend` 后执行 `node --test test/sync-source.test.js test/sync-reliability.test.js test/sync-inventory.test.js test/sync-session.test.js test/sync-load.test.js` |
| 单个后端模块 | `cd Backend` 后执行 `node --test test/configuration.test.js`，按模块替换文件名 |
| ZIP、清单和整理 | `cd Backend` 后执行 `node --test test/archive.test.js test/checklist-page.test.js test/mail-organization.test.js`。渲染依赖同完整回归 |
| Swift 核心逻辑 | `swift test`；若宏插件未加载，使用测试脚本中的插件参数 |
| 客户端导航与选择 | `swift test --filter BoxmailTests`；宏插件参数同上 |
| 分页、正文点击与窗口缩放 | 分别以 `swift test --filter <测试名>` 执行 `AttachmentPageStoreTests`、`OrganizationPageStoreTests`、`ComposerTextHitTestingTests` 或 `WindowZoomTests`；宏插件参数同上 |
| 控件、表格与面板布局 | 分别执行 `swift test --filter ControlLayoutTests` 与 `swift test --filter WorkspaceLayoutTests`；宏插件参数同上 |
| 全量编译 | `swift build`，同时编译客户端与 PPT 可执行目标 |
| App 构建与启动 | `./script/build_and_run.sh --verify` |
| 调试启动 | `./script/build_and_run.sh --debug` |

日常开发模式会关闭已运行的 Boxmail，构建后启动 `dist/Boxmail.app`；`--verify` 另检查进程存活，不代替界面及真实服务联调。`--review` 使用独立验收副本，发布打包模式不关闭或启动日常 App。独立后端的启动参数见后端文档。

本地回归测试保留在 `Backend/test/`、`Tests/BoxmailCoreTests/` 和 `Tests/BoxmailTests/`，使用临时目录、模拟 IMAP / AI 和本机 TLS SMTP，不访问真实邮箱、不发送外部邮件、不调用云端 AI。SMTP 测试需要系统 `openssl`。测试应验证数据契约、故障处理或用户行为，避免重复实现细节。

孤立后端夹具通过 Node.js 的 `detached` 子进程建立独立会话和进程组，匹配 Foundation 启动后端的隔离方式，避免启动器退出后的进程组清理干扰断言；原运行时及覆盖后的运行时均要求实际回收并释放目录锁。

配置迁移的实际客户端流程复用 `BoxmailCore.ConfigurationTransfer`。`ConfigurationTransferIntegrationTests.swift` 启动两个隔离后端，经真实 HTTP、SQLite 和 JSON 文件检查多服务商参数与凭证往返、账号映射、版本 1 迁移和预览冲突；凭证写入失败、提交失败和响应丢失由独立行为测试覆盖。测试密钥均为合成值，并检查数据库未写入这些值。

### PPT 合成样例

`Backend/test/responses.test.js` 使用以下 5 份附件，均无用户邮件数据，全部保留在 `Backend/test/fixtures/`，不进入 Release App。

| 文件 | 验证用途 |
| --- | --- |
| `two-slides.pptx` | 两页中文、截止时间、预算、内嵌图片和柱状图 |
| `two-slides.ppt` | 同内容的旧版 PowerPoint 格式 |
| `image-only.pptx` | 无提取文字的图片型幻灯片 |
| `hidden-slide.pptx` | 隐藏页展开、顺序及原件不变 |
| `twenty-one-slides.pptx` | 超过 20 页时拒绝分析 |

样例曾用 python-pptx 和 LibreOffice 生成，这些工具不是运行依赖。运行只用 macOS Quick Look、WebKit 和 PDFKit。直接执行 `npm test --prefix Backend` 时，缺少原生组件会跳过对应渲染测试；完整回归使用 `test.sh` 并检查跳过数量。

### 性能与资源测量

| 命令 | 负载及验证范围 |
| --- | --- |
| `node script/benchmark.mjs` | 默认 2400 封合成邮件、四个账户；检查索引、联系人、会话、普通及聚合分页、无变化同步和重复下载 |
| `node script/benchmark-startup.mjs` | 三个独立后端进程；测量模块载入、元数据、首屏、详情及会话就绪时间与 RSS |
| `node script/benchmark-runtime.mjs` | 缓存追加同步、12 个流式 AI 任务、三次 20 MB 图片上传和三次 20 页 PDF 分析 |
| `node --expose-gc script/benchmark-review.mjs` | 草稿匹配、邮件与附件投影、ZIP 缓存、分类及垃圾箱，共九个场景；可追加另一份快照的绝对 Backend 路径 |
| `node --expose-gc script/benchmark-workspace-lists.mjs` | 12,000 封合成邮件、1,105 个附件，测量分类与附件首尾页查询、响应大小及操作期堆增长 |
| `BOXMAIL_BENCHMARK_ROUNDS=40 node --expose-gc script/benchmark-runtime.mjs ai` | 120 个连续 AI 任务，检查任务完成、保存结果、流式输出及 GC 前后资源 |

基准在临时目录生成数据，只使用本机模拟服务，不读取日常 App 数据或凭证文件。查询取多次中位数，启动使用独立进程，运行时模式分别建立新进程。比较版本时使用相同 Node.js、数据规模和脚本，串行运行，避免与构建或测试争用 CPU。

草稿与 ZIP 等九场景基准每个场景使用三个独立进程，分页专项在同一进程重复七次；均取中位数并排除夹具准备和 GC 时间。操作期堆增长是 GC 后到操作结束的差值，不是峰值。比较时保留两端源码和脚本标识，说明基线是发布标签还是工作区快照；不要把开发过程中的单次采样写成持续有效的性能保证。

富文本基准为 `script/benchmark-rich-text.swift`。在仓库根目录编译并运行增量模式：

```bash
mkdir -p .scratch/benchmarks
swiftc -O -D INCREMENTAL \
  Sources/BoxmailCore/RichTextDocument.swift \
  Sources/BoxmailCore/RichTextStyle.swift \
  Sources/BoxmailCore/RichTextListLayout.swift \
  Sources/BoxmailCore/RichTextDocumentProjection.swift \
  script/benchmark-rich-text.swift -o .scratch/benchmarks/rich-text
.scratch/benchmarks/rich-text
```

对照完整转换时移除 `-D INCREMENTAL`，其余工具链、优化选项与负载保持一致；比较历史实现则使用对应快照的源文件。脚本预先建立 49.5 万字符文档，再连续七次单字替换，测量语义投影，不包含 TextKit 排版或整窗绘制。

发件人聚合快照只保留一份匹配元数据，不保存正文；SQLite 写入、查询变化、事务回滚、备份恢复或数据库连接变化后失效。重复读取与首次扫描应分别测量，首次扫描仍与匹配邮件数量有关。

后端 RSS 和 HTTP 就绪时间不包含客户端、WebKit、系统冷启动与真实网络；GC 后的 JS 堆也不等于操作系统已回收内存，短期测试不能证明长期无泄漏。原生验收需单独记录客户端、后端及 WebKit 的测量范围。需要留存的原始 JSON、截图和日志放在本机 `artifacts/` 或 `.scratch/`，验证完成后清理一次性结果；对外结论与适用范围合并到变更记录。

### 同步与日志故障复现

`Backend/test/sync-load.test.js` 使用六个合成账户，每个账户 1001 封邮件，验证并发上限、排队取消、一个账户超时后其余账户完成，以及重试不重复下载；另检查会话清单失效、无进展看门狗和解析子进程退出。客户端 `MailSyncLifecycleTests.swift` 验证丢失或延迟的启动响应不会挡住进度轮询，查询连续失败后请求停止，内容刷新不延长同步忙碌状态，客户端任务已取消时仍发出独立且有期限的服务器停止请求。

同步回归检查会话内复用 UID 清单，避免每批下载重新扫描；它验证查询次数与下载完整性，真实服务商网络耗时及设备资源仍需单独测量。

“设置 > 开发者”导出 ZIP，可在同步中或服务无响应时收集已落盘日志。应用和后端各保留约 3 MB，默认持续记录关键事件；只用匿名账户、阶段、计数、错误分类与耗时，禁止传入原始错误描述、邮件主题、正文或凭证。不要把配置 JSON 或真实数据目录作为诊断附件。

`Backend/test/parser-isolation.test.js` 注入原生 SIGABRT、外部缓冲区占用及阻塞循环，检查解析子进程隔离、RSS 保护、断点与附件保留、取消和所有者失联后的进程回收。诊断分类不保存原始标准错误或文档内容；只复用自建进程组，不终止其他 Node 进程。后端 RSS / CPU 计数不包含这些子进程。历史修复与验证范围见[变更记录](../CHANGELOG.md)。

启动日志 `startup.phase` 按 service、snapshot、apply、first-page 和 selected-content 记录本地耗时，`startup.ready` 仅表示数据就绪，不包含 LaunchServices 启动和后续 WebKit 绘制。日志只记录匿名阶段、数量与耗时。`message-header.js` 将列表的 `to`、`cc`、`bcc`、`replyTo` 展示字符串限制为 2,048 字符，发件人聚合复用该投影与有界预览；详情和回复收件人必须读取完整记录。

主状态 `/state` 的 `drafts` 始终为轻量头部：body 清空、转发大字段省略、bodyLoaded=false，预览仅投影有限字符。阅读通过 `/messages/draft:<id>` 取得合并原文；写信编辑通过 `GET /drafts/<id>` 取得原始可编辑正文和独立转发快照。所有草稿入口共用按需加载，迟到响应受请求代次和 restoreRevision 保护；`POST /drafts` 拒绝 bodyLoaded=false，避免将空头部保存为正文。20 MB 转发草稿的主状态响应有大小上限回归。

### ZIP 资料包与附件预览

`archive-reader.js` 使用精确锁定的 yauzl 3.4.0，通过 `ParserProcess` 读取目录和有界解压，校验实际大小与 CRC；文件从不解压到其提供的路径。`archive-service.js` 负责父附件、内容指纹与包内读取，`archive-analysis.js` 复用普通文件的 `extractText`、`modelFile` 与模型请求，并校验结构化汇总来源。目录、子文件结果和汇总以父附件 ID 独立保存为 archive 记录，附件仅保存 archiveInfo 轻量投影，SQLite 结构版本仍为 2；详情读取再按需组合，备份恢复校验并重建投影。邮件批量任务将 ZIP 作为一项，内部逐文件保存，暂停、重启和重试沿用任务恢复流程。附件列表搜索包含已读取的清单路径与整体分析，不扫描逐文件理解结果。

ZIP 缓存按路径、设备、inode、大小和 mtime／ctime 核对文件身份，稳定命中不重读原包；实际读取包内文件及理解仍使用原始字节。新写入、旧缓存迁移和读取均验证清单，先解码文件名再校验安全路径。备份校验重新派生或移除每份附件的 `archiveInfo`，启动也防护详情缺失；损坏时仅丢弃派生缓存，保留邮件、原附件及有效结果。完整备份从只读 SQLite 快照查询计数和附件 id／name／path，避免水合全部附件与归档详情；恢复前重新派生草稿富文本并清洗转发 HTML。

`AttachmentPreviewLoader` 在后台解码、写入独立临时文件及验证 PDF，界面只接收完成结果，取消和失败都清理文件。普通预览、ZIP 容器和单文件预览分别由独立视图负责。

### 邮件 AI 上下文

当前桌面端从阅读区翻译、清单整理和写信浮层发起模型请求。分别由 `mail-translation.js`、`mail-organization.js` 和 `writing-preview.js` 定义请求范围。旧整封分析与附件结果读取本机记录，保留 `mail-ai-context.js` 的旧客户端兼容。任务指令、上传清理、输出校验与模型协议分别由 `ai-instructions.js`、`responses.js` 和 `ai-protocols.js` 处理。

请求范围、结果来源及数据迁移见 [AI 上下文](MAIL_AI_CONTEXT.md)，接口字段见 [后端文档](../Backend/README.md#当前客户端的翻译写作及历史接口)。

### 共用列表与分页

`WorkspaceListSurface` 固定标题与页脚，内部记录区滚动。`WorkspaceList` 提供行分隔、选择状态和空态，`ListPagination` 管理分页操作。清单通过 `GET /checklist` 按来源分页，通知可用 `followUpId` 定位事项所在页。`PagedListStore` 按请求代次隔离账户、筛选条件及刷新中的旧响应。

当前客户端从来源邮件打开附件。后端继续提供旧附件和分类分页接口，契约见 [后端文档](../Backend/README.md#邮件账户与附件)。搜索读取现有索引和缓存，不触发提取或模型请求。`/state?compact=1&previews=0` 仍保留轻量附件头部，供邮件和草稿引用。

### 主窗口缩放

窗口顶部只在两个空白区域使用 `WindowTitlebarRegion`；隐藏标题栏可能先于 NSView 消费双击，因此桥接在挂接时安装局部鼠标监视，仅拦截所属窗口、空白区域内的双击，脱离或销毁时移除；保留搜索框和工具按钮的原生输入。`WindowZoomController` 由 ContentView 持有，按窗口保存缩放前 frame，在当前 NSScreen.visibleFrame 内最大化，第二次恢复；两向均调用 NSWindow.setFrame(_:display:animate:) 的 AppKit 原生动画，不自定义时长或曲线。初始已最大化且没有历史 frame 时，按 MainWindowLayout 的默认 1440 × 900 尺寸生成居中的还原窗口；小屏限制在可用区域的 85%，同时遵守最小尺寸。MainWindowLayout 也为主场景提供默认及最小尺寸，避免两处配置漂移。手动缩放后以新尺寸作为下一次恢复基准，不进入系统全屏。

`WindowZoomTests.swift` 覆盖历史尺寸恢复、初始最大化、边缘误差、小屏、负坐标屏幕及标题区域命中。原生检查同时核对动画、拖动和搜索／按钮输入，验证结果与边界见变更记录。

### 富文本、服务器草稿与写作

字号、颜色和可选签名起点使用现有 JSON 记录存储。SQLite `user_version` 仍为 2，旧草稿及备份允许缺少这些字段。

- 富文本由 `RichTextDocument` 的段落与文字片段表达，`RichTextStyle` 定义字号与不透明 sRGB 颜色，`RichTextController` 负责选区、格式命令和撤销，`RichTextFormatBar` 负责格式控件，`RichTextEditor` 仅桥接 TextKit。文字片段的可选 `fontSize` 使用 pt，范围 8 至 72，最多两位小数；可选 `color` 使用 `#RRGGBB`，省略表示默认 14 pt / `#232D3D`，兼容既有草稿。混合选区提供状态反馈，空选区仅修改输入属性，格式命令保留其他片段属性。后端 `rich-text-style.js` 统一校验和 HTML 样式转换，`rich-text.js` 派生 `bodyHTML` 和纯文本 `body`；同步导入继承并规范化安全的字号、颜色，不保留任意 CSS。编辑器不导入可执行 HTML 或外部资源，保留选区、撤销和中文组合输入。`bodyHTML`、`richText` 与转发快照均从草稿头部及有界搜索投影中剔除。
- `RichTextDocumentProjection` 缓存段落语义，普通输入局部更新；编辑范围有歧义、格式变化或多段编辑时回退完整转换。局部片段到达文末时须与完整转换保持相同的尾部空段落形状；列表标记按内容坐标映射 UTF-16 选区。`RichTextDocumentProjectionTests.swift` 覆盖各位置连续编辑及尾部换行，每步与完整转换比对，继续保留输入法和原生撤销行为。
- `PlaceholderTextView` 通过 TextKit 段落间距和本地绘制呈现签名分隔条。`signatureStart` 是草稿内可选的 UTF-16 位置，发送只序列化正文与签名。旧草稿可按账户签名后缀识别。采用完整候选后，光标停在签名前的正文空行。`ComposerTextHitTestingTests.swift` 核对正文空白行、宽窄窗口、签名编辑、撤销和保存往返。
- `RichTextListLayout` 从每项开头文字派生标记字号、颜色与折行缩进，空白项延续上一行末尾格式；重建和 TextKit 正文变化共用此规则，包含修改字号、继续输入及撤销。标记不进入语义 runs。HTML 在 `li` 上设置标记字号和颜色，并在每个 run 上明确默认样式，避免大字号列表项把原有小字号片段一起放大。
- 草稿随 `syncAccount` 同步，也可限定 `folder=drafts`；复用账户锁、逐条 IMAP 期限、取消和独立 MIME 解析进程。旧版本中只读缓存的服务器草稿迁为可编辑草稿，保留正文和附件。`draft-sync.js` 在 APPEND 前保存随机 MIME token 与内容指纹，重连后核对结果；正文版本与远端 UID / UIDVALIDITY 分开，另以 IMAP 端点及登录身份指纹限制远端绑定与清理，配置改变后保留本机副本待确认。上传返回时重新读取当前草稿，避免覆盖同时发生的编辑、删除和账户切换。
- `DraftSyncIndex` 独立维护轻量匹配字段，跟随 Repository 变更与事务回滚更新，避免逐封全量解析本机草稿。`DraftReadFailures` 按服务器身份、UIDVALIDITY、UID 和大小记录最多 100 个短期失败，60 秒后重试；单封内容异常作为警告继续处理，连接及安全清理错误仍中断当前连接。无法读取的服务器替换版本保留本机内容与远端绑定，不误判为删除。
- `GET /drafts/:id` 及创建回复的响应提供内容修订值 `revision`；客户端保存时回传，旧修订的不同内容返回 409，相同内容重试可安全确认。远端更新保留本机冲突副本，远端删除不直接删除或重新上传本机草稿。删除和发送产生持久化 `draftDeletion` 清理记录；删除意图可按 token／Message-ID 重新对账；连续三轮无法核对后提示人工处理，仍保留记录与备份。执行删除前重新确认目标 UID 与 UIDVALIDITY，且必须支持 UIDPLUS；并发删除后确认目标已不存在则完成清理，目标仍存在则保留意图。
- 富文本正文上限仍为 500,000 字符，链接与文字的累计输入另有 4 MB 上限；服务器草稿 MIME 编码后最多 25 MB，超限留在本机。Boxmail 同步的转发 MIME 使用独立的编辑区与引用区标记，其他安装读取时仍保持快照分离；外部客户端移除标记后按其保存的正文导入。
- `conversation-ai.js` 复用同账户引用链，正文按最新优先分配输入预算，再按时间顺序提供模型；最多 50 封、每封 16,000 字符、总计 120,000 字符，并明确部分上下文。输出逐项校验来源 ID，保存会话指纹及来源内容指纹；回复采用时再次核对，关联最新往来。结果仅保存为 Job，单封摘要和已编辑草稿不被覆盖。

相关回归为 `Backend/test/rich-text.test.js`、`draft-sync.test.js`、`conversation-ai.test.js`，以及 Swift 的 `RichTextTests`、`RichTextEditorTests`、`RichTextColorMenuTests` 与草稿加载保护。`RichTextFormatBar` 使用 `CossMenu` 选择字号和预设色，自定颜色复用 `CossColorEditor`，链接表单使用 `CossPopover`。菜单色样与图标分别绘制，像素回归核对实际 sRGB 颜色。原生隔离验收已核对格式编辑、保存重开、宽窄布局和依据邮件跳转；实际 IMAP 服务商、其他邮件客户端、真实 AI 服务及 VoiceOver 全流程仍需单独验证。

各版本的编译、回归与原生验收范围统一记录在变更记录中。

### 邮件字符与数据解码

0.1.4 兼容附件 `contentType` 为 false、空值或无效 MIME 的旧缓存；`mailparser` 对空 `Content-Type:` 会实际返回 false，默认参数只覆盖 undefined，不能修正这类值。`attachment-metadata.js` 统一未知 MIME 类型，Repository 启动只投影检查 MIME 元数据，再分批事务修正异常记录。新写入、完整及紧凑读取、元数据接口和转发副本使用同一规则。

Swift 仅对这项可缺省的描述字段提供回退，附件身份、大小及其他必填字段仍严格验证。修复不触碰附件文件或已有文本、分析；`data.attachment.repaired` 记录字段、实际类型、阶段及匿名记录编号。`attachment-metadata.test.js` 从真实 MIME 复现开始，覆盖持久化、原件一致性、转发及完整备份；Swift HTTP 回归将异常放在第 4,135 个附件，验证 12,001 封邮件的加载、设置保存和退出重启。

本机诊断测试包使用 `./script/build_and_run.sh --package-test`，输出独立 build 目录，保留日常 App 和既有发布包；此模式不创建标签、不推送，不通过正式发布的干净源码检查。交付元数据必须标明工作区快照和基线提交，正式发布仍使用 `package_app.sh` 的干净检出与标签流程。

自 0.1.3 起兼容 JavaScript 字符串截断切开 UTF-16 代理对，以及旧邮件头编码产生未配对代理项时，JSON 响应被 Swift 拒绝的问题。`unicode.js` 在文本片段边界保留完整字符，新记录与 HTTP / SSE 字符串值规范化；旧记录读取时兼容，不批量删除或重建原邮件。有效正文、HTML 和附件字节保持原状，无法表示的孤立代理项以替代字符显示。

`ContentWireIntegrationTests.swift` 启动隔离后端，创建六账户、12,001 封合成邮件，并用真实 MIME 解码产生旧编码异常后直接写入旧记录。通过 HTTP 及 Swift 模型验证首次加载、单封正文、分组查询、设置保存及同目录重启。`unicode-content.test.js` 另检查摘要截断、旧缓存、附件原字节和 SSE；`parser-isolation.test.js` 检查附件驻留内存回收后下一封 MIME 仍可读取。

解码诊断记录 `phase=decode`、精确字段路径、数组下标、期望与实际类型、响应字节数，以及匿名账户和记录编号；未知字典键替换为 `:key`，不写入原始描述和值。`requestID` 关联客户端、HTTP 和同步解析任务；后端在异常字符被替换前记录 `data.unicode.repaired`，包括触发字段和处理阶段。首次问题立即落盘，同一字段和记录的重复问题每 30 秒计数合并，聚合行保留最近请求编号；`diagnostics.dropped` 报告有界写入队列因拥塞省略的条数。

### 品牌图标

品牌源图与客户端共用 `Sources/BoxmailCore/Resources/BoxmailMark.png`。图标处理及裁切参数见 `script/generate_icon.swift`。客户端通过 `BoxmailBrand` 读取资源并缓存图片，侧栏按 28 pt 显示。

`script/generate_icon.swift` 从同一原始图片生成 16、32、64、128、256、512 和 1024 像素的标准 iconset；裁切原图外围 5% 并施加圆角遮罩，统一主体尺寸和透明留白，再由 `iconutil` 转为 `Boxmail.icns`。构建脚本在图片或生成脚本变更时重建图标，App 启动时使用包内图标更新 Dock 与“关于”窗口。更换品牌素材后检查浅色与深色背景、小尺寸可辨识性、侧栏及实际安装包，避免只替换源码中的图片。

### 代码与异步状态约定

- Swift 和 JavaScript 使用两空格缩进；Swift 修改范围使用工具链自带的 `swift-format` 整理，保留未修改代码的现有布局。
- `MailStore` 保持主线程状态隔离，调用统一的后端实例；HTTP 请求序列化、响应及 SSE 解码在主线程之外执行，完整结果回到主线程后再更新观察状态。
- 元数据、列表、详情及会话响应按各自请求版本检查；恢复完成后、刷新前递增数据恢复版本，忽略旧数据库的在途结果。附件缓存仅接收当前邮件、展开会话或仍打开预览所需的内容。
- 草稿打开与回复创建共用请求版本；已打开写信窗口时拒绝替换，迟到响应不能覆盖后来创建的草稿、设置窗口或恢复后的数据。保存关闭与发送期间同时禁用原生输入和 SwiftUI 控件，发送使用确认操作开始时的账户。
- SQLite 事务只执行同步记录操作；先准备附件文件，再将邮件、附件及关联引用一并提交，失败清理本次准备的文件。恢复成功后同时重建索引并使邮件预览缓存失效。
- IMAP 待提交操作复用逐条命令期限与取消处理，失败保留待同步更改；不以整批总时长替代单条命令期限。

## 联调与界面检查

使用独立测试账号、收件人、数据目录和合成附件。原生验收副本使用独立 Bundle ID。App 可通过绝对路径 `BOXMAIL_DATA` 使用临时目录，凭证默认使用该目录的 `.env`，不改变日常数据位置。隔离验收时不要指定日常使用的 `BOXMAIL_ENV_FILE`，也不要与正在运行的 App 共用后端目录。

| 流程 | 检查重点 |
| --- | --- |
| 账户与同步 | 两种 TLS、默认与自定义端口、认证错误、千封历史回填、断网及重启、UIDVALIDITY 和跨账户隔离 |
| 阅读与会话 | HTML / CID / 远程图片开关、时间线及引用折叠、逐封回复和原身份、恢复及取消归档的来源 |
| 写信 | 空收件人／抄送／密送的鼠标与 Tab 切换、关键词联系人浮层、中文输入法、键盘和跨字段去重、字号与颜色、列表标记继承及撤销、聚焦下划线、签名置底、点击正文空白行、采用候选后在正文续写及签名编辑撤销、粘贴文件及图片、草稿恢复 |
| 来源附件与 ZIP | 按文件名搜索、打开来源邮件、原件预览、同封切换、转发保留附件、包内文件目录、旧分析与来源跳转 |
| 清单与标签 | 条件试用与确认、人工移除保护、多标签筛选、账户隔离、自动整理的 UID 起点、摘要隐藏与恢复 |
| 共用控件与历史结果 | 间距和基线、键盘焦点、长待办换行、覆盖清单和来源跳转 |
| AI | 翻译按语言持久化、写作候选采用与撤销、旧 AI 结果只读打开、整理输入范围及失败重试 |
| 搜索 | 中文、附件内容、组合条件、跨账户、草稿编辑身份、日期边界、闰年及翻月后保留条件 |
| 设置与数据 | 模型列表重启和失败保留、配置合并及凭证引用、跨目录完整备份恢复、原排版译文及总结收录状态、附件字节与重启、校验及回滚、目录迁移和外置盘缺失 |
| 布局与预览 | 顶部双击的原生最大化／还原动画、初始最大化默认还原、小屏及多屏、宽窄及低高度窗口、嵌套面板、固定底栏、294 pt 邮件栏、四项筛选、紧凑列表、原生多选、快捷键与撤销、年月菜单、PDF / Word / XLSX / PPT 原文件及无轨道滚动条 |
| 生命周期 | 退出时子进程和文件锁释放、任务中断状态、再次启动后的数据和凭证行为 |

结果不确定的发送先核对实际投递，不能自动重试；永久清空只在明确可丢弃的测试邮箱中执行。新增操作保留现有发送确认、分类审阅和撤销机制。

### 邮件与工作区状态

`ActivityPresentation` 对已有审计事件分组。`ActivityView` 结合当前同步状态显示待处理操作、规则记录、整理记录与 AI 用量。`MailSourceContext` 维护来源跳转，账户、查询或恢复版本改变时按现有请求代次重新加载。

阅读区的回复、全部回复和转发沿用 `MailStore.newDraft`，由后端处理原账户、收件人与转发快照。写作浮层由格式栏或正文选区的右键菜单打开，采用候选时编辑当前草稿。附件从来源邮件预览或下载。

隔离原生验收可执行 `env -u BOXMAIL_ENV_FILE BOXMAIL_DATA="$(mktemp -d /tmp/boxmail-review.XXXXXX)" ./script/build_and_run.sh --review`。此模式使用 `com.boxmail.desktop.review`、独立进程名称 `Boxmail Review` 和 `artifacts/ui-review/Boxmail Review.app`，便于自动化准确选择实例，不关闭日常 App；脚本要求指定数据目录。若系统从 Finder 重新打开验收副本并丢失环境变量，会改用独立的默认目录 `~/Library/Application Support/Boxmail Review/`。日常开发版与发布包默认关闭演示数据初始化，只有隔离验收模式启用；关闭初始化不会清理已有数据。只在合成数据中验证批量删除和撤销。

原生验收覆盖账户切换、列表选择、原邮件跳转、会话、未读筛选、归档和撤销、草稿恢复、HTML 转发、译文切换及原文件预览。无障碍名称通过 AX 树检查；VoiceOver 全流程、真实外部投递及其他服务商不属于本机合成回归的验证结论。

### 后端生命周期

`BoxmailCore.LocalBackendProcess` 持有进程及数据目录锁，启动后关闭父进程中用于 stdin 继承的重复文件描述符，避免已结束的子进程仍通过本地引用占锁。App 退出先取消客户端任务，再等待后端关闭；服务的清理期限为 3 秒，App 在 4 秒后仍未等到退出时只终止自己创建的子进程，确认退出后才释放租约。

`Backend/src/service-lifecycle.js` 在数据库初始化前安装退出处理，检查父进程并通过 stdout 管道检测 App 消失。已有旧服务占锁时，客户端仅回收同用户、同一运行时路径、stdin 指向同一锁文件且父进程已为 1 的孤立后端；其他活跃 App 和无关 Node 进程继续保留。就绪检查使用 `/health`，完整状态另按需读取。

### 界面约定

颜色、字体、尺寸、断点、外观和动效统一维护在 [UI 规范](DESIGN.md)，本节只保留状态与原生桥接约定。

- 设置与编辑面板复用 `SettingsActionBar`、`SettingsFieldRow`、`SettingsTransferRow` 和 `.workspaceSheet()`。已有输入在失败时保留，配置确认期间继续锁定父设置页；动作状态由 `SettingsActionState` 管理。
- 邮件列表的 Binding 只提交当前查询中的用户选择，跳转和刷新独立协调。`MailRevealRequest` 由目标行消费，重复打开可重新定位，普通刷新不抢回滚动位置。快捷键由 `FocusedValue` 限定在列表，文字编辑沿用原生行为。
- 手动单封与批量操作共用 `/messages/batch`，撤销按 `expected` 核对冲突；自动已读不占用手动撤销记录，恢复备份后清空旧撤销与选择。
- `RecipientDetailsView` 共用邮件头、HTML 与纯文本引用、转发及草稿搜索的收件信息。`RecipientAddressList` 负责只读文字和滚动，`ScrollEventRouting` 按当前鼠标位置及 `bounds` 与 `visibleRect` 的交集命中；移到正文立即交还外层，避免可见矩形越界或旧事件目标占用滚轮。HTML 脚本只识别字段和报告占位，SwiftUI 组件回填高度，切换文档重置状态；文字更新保留原始节点映射。
- `RecipientEntryView` 只在 `isEnabled` 真正变化时赋值，避免焦点刷新重复触发系统自动填充。空关键词不显示联系人浮层，输入法、选区、鼠标与 Tab 交接保持原生行为。
- HTML 转发以 `forwardedHTML` / `forwardedText` 保存快照，编辑正文只含说明和签名；未编辑的旧引用可恢复原排版，已编辑内容保留。预览折叠不写回快照，发送合并两种正文并转换 data 图片为 CID。
- AI 通过认证的 `/ai/events` SSE 逐步显示，中间输出不持久化，结束后校验再提交；分类确认和草稿采用等待完整结果。译文按文字节点 ID 更新并转义，链接、图片、样式、邮件脚本和联网限制保持原策略。
- 摘要显隐只更新 `summaryHidden`，不删除 `summary`；列表、已移除与撤销共用 `/summaries/visibility`。旧整封分析从来源邮件的「历史结果…」查看。旧保存视图的「AI 已总结」条件继续按实际结果判断。

## 本机凭证与签名

`EnvCredentialStore` 读写当前数据目录的 `.env`，客户端通过 `CredentialService` 访问；`BOXMAIL_ENV_FILE` 可覆盖为其他绝对路径，构建脚本会将其传入启动的 App。文件每次读取，不缓存凭证，也不读取进程中的同名密钥变量；后台同步无需交互。普通偏好保存不得清空尚未修改的 API Key。账户保存与修改过的 AI Key 通过 `CredentialUpdate` 先写新的 `BOXMAIL_CONFIGURATION_<UUID>` 条目，再由 `/accounts` 或 `/settings` 提交引用。账户记录和引用在同一 SQLite 事务中保存，API Key 与偏好在同一设置记录中保存。后端只接受当前保存对象所属的合法引用，不接收密钥正文。

凭证文件写入失败时清理本次已暂存条目，不提交设置；提交失败后检查 `/state` 的引用，确认已生效则按成功处理。无法确认或请求仍可能在途时，保留暂存条目供已提交的配置读取，原凭证不被覆盖。列表刷新失败不能反转已成功的账户或设置保存结果。旧的直接命名和导入生成引用继续兼容；已有绑定优先读取其生成条目。

配置导入仅为文件中的非空凭证先写新条目，再事务提交引用；空值仅在端点、协议及邮箱身份一致时保留本机绑定。`credential-bindings.js` 为配置导入和备份恢复提供同一规则，地址或身份变化时生成空的新引用并返回 `credentialsRequired`，客户端按账户和服务商列出重填项。确认页显示 IMAP/SMTP 主机、端口、加密方式和用户名；确认导入被拒绝时只清理本次条目，结果无法确认时保留可能生效的凭证。密钥不进入 SQLite、任务、日志或模型缓存。

文件使用 UTF-8 的 `KEY=VALUE` 格式，保留其他变量及独立注释；双引号值使用 JSON 转义，单引号值为原文，不执行变量展开。写入通过同目录的 `0600` 临时文件原子替换，格式错误时拒绝覆盖；符号链接和目录不能作为凭证文件。完整 ZIP 不包含 `.env`，默认文件随数据目录迁移，外部指定路径保持原状。示例及命名见根目录 `.env.example` 和使用指南。旧钥匙串不自动访问，升级需重新保存凭证或导入旧配置 JSON。

App 仍需代码签名以正常启动。默认使用 `codesign --sign -` 临时签名；使用带私钥的固定签名证书时：

```bash
security find-identity -v -p codesigning
BOXMAIL_SIGNING_IDENTITY="证书的 SHA-1 指纹" ./script/build_and_run.sh --verify
codesign -dvvv -r- dist/Boxmail.app
codesign --verify --deep --strict dist/Boxmail.app
```

也可将指纹单独写入根目录 `.boxmail-signing-identity`，该文件已忽略；环境变量优先。凭证文件读取与签名身份无关；正式签名和公证仍需另行验证。

## 版本与打包

普通修复可继续使用当前版本。制作安装包时，同步更新以下文件的版本或发布内容。

| 文件 | 内容 |
| --- | --- |
| `VERSION` | App 版本来源 |
| `Backend/package.json`、`Backend/package-lock.json` | 后端包版本，可用 `npm version <版本> --prefix Backend --no-git-tag-version` |
| `BUILD` | 构建号来源，构建脚本校验并写入 `CFBundleVersion`；打包读取同次构建的 Info.plist |
| `CHANGELOG.md`、`README.md`、`docs/RELEASE_NOTES.md` | 源码版本、更新说明和验证记录 |
| `docs/USER_GUIDE.md`、`docs/DESIGN.md`、`docs/DEVELOPMENT.md`、`docs/ROADMAP.md`、`docs/MAIL_AI_CONTEXT.md`、`Backend/README.md` | 适用版本、当前操作、UI 规范、接口契约、回归基线及已发布范围 |

1. 完成适用的回归、编译和原生联调，检查差异，不提交个人数据。
2. 提交源码和文档后建立 `v<版本>` 标签，从干净标签或独立检出执行 `./script/package_app.sh`。脚本拒绝未提交及未跟踪的源码修改。
3. 核对版本、构建号、内置资源、Node.js 及原生依赖、嵌套签名、包内说明、源码标签和完整提交号。
4. 校验 ZIP 的 SHA-256、解压一致性及签名，并用独立空目录检查首次启动。最低系统、其他架构和设备需分别验证。
5. 对外发布时，再推送提交和标签，并上传 ZIP 与 SHA-256 文件。核对远端提交、资产大小和校验值。

App 发布后，在官网独立分支同步版本、下载链接、系统要求及对应版本的指南链接。官网截图与功能说明以公开安装包为准，不将未发布的源码变化写成下载版能力；本地内容位于 `website/`，预览方式见官网分支的 `README.md`。

发布模式以 Release 构建，包内含后端源码及生产依赖、SwiftPM 资源和内置运行时。界面图标位于 `Boxmail_Boxmail.bundle`，核心共享资源位于 `Boxmail_BoxmailCore.bundle`。发布包关闭演示数据，日常 App 在打包期间继续运行。`docs/USER_GUIDE.md` 复制为包内 `使用说明.md`，`docs/RELEASE_NOTES.md` 复制为 `更新说明.md`。两份说明均可在解压后直接阅读。`版本信息.txt`记录版本、源码标识和上海时区生成时间。产物在 `dist/`，日常 App 为 `dist/Boxmail.app`。

已发布标签保持不动，同版本重打包使用新的 `v<版本>-repack.N` 标签。GitHub Release 按版本发布安装包；历史版本及源码可通过 Release、Git 提交与标签追溯。

## 文档与本地产物

[README](../README.md) 维护项目入口与文档目录；[使用指南](USER_GUIDE.md) 维护操作和限制，[UI 规范](DESIGN.md) 维护视觉及交互尺寸，本文维护实现与开发流程，[后端接口](../Backend/README.md) 维护数据契约。[AI 上下文](MAIL_AI_CONTEXT.md) 记录模型输入范围和旧数据兼容。路线图列出后续验证和候选，版本变化及验收范围写入[变更记录](../CHANGELOG.md)。

未发布变化明确标注为当前源码或日常开发版，不改写历史安装包的能力与验证基线；删除章节或移动内容时同步修复相对链接和锚点，不再维护旧行号及重复进度报告。

`website/` 是官网独立分支的本地内容，按该分支维护和发布，不作为 App 运行资源或安装包内容。往期调研和代码审查可从对应发布标签追溯。当前实现写入各自的维护文档。

| 本地内容 | 维护方式 |
| --- | --- |
| `Tests/`、`Backend/test/` | 保留本地回归源码与样例，已移出 Git 索引并由 `.gitignore` 排除；构建不依赖其存在 |
| `.build/` | Swift 编译缓存，可清理，下次构建自动重建 |
| `dist/Boxmail.app` | 日常开发版，保留供运行；发布 ZIP 和 SHA-256 文件独立保留 |
| `artifacts/`、`.scratch/` | 保存隔离验收输出。测试 App、解压副本、截图和日志验收后可清理。实际数据备份另行保留 |
| `Backend/node_modules/` | 本机依赖，不提交 Git；缺少时通过 `npm ci --prefix Backend` 重建 |
| 数据库、`.env`、日志和签名配置 | 不提交 Git；真实数据与凭证不随构建清理 |

`.impeccable/critique/` 和 `.impeccable/review/` 不提交 Git，项目配置保留在 `.impeccable/config.json`。各发布标签可用于追溯当时的源码和文档。

本机回归不能代替真实外部投递、其他邮件或 AI 服务商、大邮箱长期性能、最低系统、Intel、屏幕阅读器及正式分发验证，实际验证范围见变更记录。


## 清单、标签、写作与兼容接口

`MailQuery.swift` 和 `mail-query.js` 共用账户、文件夹、关键词、筛选及标签条件。`labelId` 用于多标签筛选，旧 `category` 继续用于已有规则与保存视图。标签成员关系和人工排除由 `mail-labels.js` 管理，分页前应用条件。`checklist-page.js` 按来源聚合摘要和事项，`follow-ups.js` 保留已收录事项的 ID、手工标题、状态和提醒。

`application-services.js` 组装领域服务。`account-sync-coordinator.js` 协调手动与 IDLE 同步，`mail-organization.js` 根据账户授权与收件箱 UID 起点入队。旧自动规则含 AI 动作时整条暂停。规则、发送计划及整理任务执行时通过 `local-credentials.js` 读取绑定的凭证，密钥不进入持久化任务或用量记录。

`ComposerWritingPopover` 持有当次写作选项并显示候选，`WritingPreferencesStore` 管理内置风格和用户预设，输出语言复用 `MailTranslationLanguage`。写作要求框使用 Command + Return 生成，组合输入期间交给原生编辑器。采用前由 `writing-preview.js` 核对原件或会话，再由客户端核对草稿与选区。采用仍可撤销。

`mail-history.js` 按来源聚合原有会话结论、回复预览及问答，旧助手和整封分析的 HTTP 路由继续兼容。附件已有分析通过各自的详情和 ZIP 目录读取。IMAP 缓存身份迁移由 `mail-source-references.js` 更新引用。备份恢复保留历史结果、写作预设与人工事项；等待中的发送计划暂停，提交中的计划转为结果不确定。

共享提示词资源由 `ai-settings.js` 和 `legacy-prompts.js` 维护。升级只替换与旧默认全文一致的提示词。自定义值、用户记录和旧结果继续保留。

完整回归用 `./script/test.sh`。保持邮件来源、恢复、安全边界和已保留的兼容接口测试。隔离 App 核对当前入口、键盘、输入法和滚动；实际结果范围见[变更记录](../CHANGELOG.md)。
