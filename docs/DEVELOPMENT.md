# 开发与维护

本文适用于 Boxmail 0.1.8（build 47），覆盖 ZIP 理解、共用列表与分页、原生窗口缩放、草稿同步及备份恢复；发布范围见[变更记录](../CHANGELOG.md)。项目启动及文档入口见 [README](../README.md)，操作行为见 [使用指南](USER_GUIDE.md)，路由和数据契约见 [后端接口](../Backend/README.md)。日常开发保持 SwiftUI、本机 Node.js 和 SQLite 的结构。

## 源码入口

| 目录或模块 | 职责 |
| --- | --- |
| `Sources/Boxmail/App/` | 应用、场景和命令 |
| `Sources/Boxmail/Views/` | 邮件、写信、搜索、附件和设置界面 |
| `Sources/Boxmail/Support/` | 设计系统、动效、滚动及原生预览桥接 |
| `Sources/Boxmail/Stores/MailStore.swift` 及扩展 | 状态、后端调用、分页、缓存、AI 输出流和任务轮询 |
| `Sources/Boxmail/Stores/AttachmentPageStore.swift`、`OrganizationPageStore.swift` | 附件与分类邮件当前页、筛选请求、取消、迟到响应和刷新版本 |
| `Sources/Boxmail/Views/WorkspaceList.swift`、`ListPagination.swift` | 共用列表滚动边界、行反馈与分页栏 |
| `Sources/Boxmail/Support/WindowTitlebarRegion.swift`、`MainWindowLayout.swift` | 主窗口标题区域交互、原生缩放及默认／最小尺寸 |
| `Sources/Boxmail/Services/` | 后端生命周期、本机凭证和配置迁移 |
| `Sources/BoxmailCore/` | 数据模型、配置归档、存储迁移、后端进程与目录锁、文本与日期逻辑 |
| `Sources/BoxmailCore/Resources/` | 共享提示词、回复态度、收件人布局及客户端品牌图片 |
| `Tests/BoxmailTests/` | 客户端导航、列表选择、邮件与附件分页状态，以及 AppKit 编辑器行为 |
| `Sources/BoxmailPresentationRenderer/` | WebKit / PDFKit 幻灯片页面生成 |
| `Backend/src/` | 协议、HTTP、任务、持久化、索引及备份 |

修改接口时同步检查 Swift 模型、后端路由和调用方；修改数据结构需设计迁移和旧数据兼容。应用版本与 SQLite 结构版本独立，当前 `user_version=2`，搜索索引为可重建派生数据。

后端 AI SDK 精确锁定为 `@earendil-works/pi-ai@1.3.0`，其内部 `pi-telemetry` 同为 1.3.0；共用 `openai@7.19.0` 和 `@anthropic-ai/sdk@0.129.0`。升级依赖时同步提交 `Backend/package.json` 和 `Backend/package-lock.json`，已有检出在更新后执行 `npm ci --prefix Backend`。协议与模型参数约定见 [后端接口](../Backend/README.md#ai-请求与任务恢复)。

## 构建与测试

在仓库根目录执行，依赖及工具链要求见 README。

```bash
./script/test.sh
git diff --check
```

构建、测试和后端启动均要求 Node.js 24.22.2 LTS 或更新的 LTS 版本，最低版本以 `Backend/package.json` 的 `engines.node` 为准，`Backend/src/check-node.js` 同时检查版本下限和 LTS 标记。构建在关闭 App 前完成检查，并按二进制内容更新内置 Node.js，避免文件时间导致旧运行时被保留。

`test.sh` 检查运行时后构建 `BoxmailPresentationRenderer`，通过 `BOXMAIL_PRESENTATION_RENDERER` 传给后端测试，再运行 Node.js 和 Swift 测试。工具链提供 `TestingMacros` 插件时显式加载，避免部分 Command Line Tools 未自动加载宏的问题。

当前源码回归覆盖 ZIP 与备份损坏缓存恢复、草稿异常和并发对账、附件及分类邮件分页、后台预览清理、富文本连续编辑，以及窗口原生缩放与默认还原。最新测试数量、原生验收和真实服务验证范围统一记录在 [CHANGELOG](../CHANGELOG.md#018--2026-11-12)，历史发布基线保留在各版本条目中。新增回归不得替换同名旧测试。

真实 HTTP/SQLite/Swift 回归包含六账户、12,001 封合成邮件及 4,135 个附件的加载、正文与 HTML 保留、设置保存和同目录重启。HTTP 夹具按会话隔离，正式测试继续覆盖凭证文件权限、手工修改、迁移、ZIP 排除密钥、WAL 强制退出、磁盘容量不足、事务回滚、网络期限与取消、JSON 主线程隔离及客户端旧响应竞态。大邮箱用例一次补齐 12073 封收件箱与 543 封已发送；AppKit/WebKit 用例检查定位、选择、分页、收件人滚动和转发预览。搜索派生索引在后台逐封处理，测试等待索引就绪，搜索请求本身不能触发全量 flush。发布时另验证正式包的图标、资源、源码、签名、首次启动及退出清理。

| 需要验证的范围 | 命令 |
| --- | --- |
| 完整回归 | `./script/test.sh` |
| 正文同步与大邮箱回归 | `cd Backend` 后执行 `node --test test/sync-source.test.js test/sync-reliability.test.js test/sync-inventory.test.js test/sync-session.test.js test/sync-load.test.js` |
| 单个后端模块 | `cd Backend` 后执行 `node --test test/configuration.test.js`，按模块替换文件名 |
| ZIP 与工作区分页 | `cd Backend` 后执行 `node --test test/archive.test.js test/attachment-page.test.js test/organization-page.test.js`；渲染依赖同完整回归 |
| Swift 核心逻辑 | `swift test`；若宏插件未加载，使用测试脚本中的插件参数 |
| 客户端导航与选择 | `swift test --filter BoxmailTests`；宏插件参数同上 |
| 分页、正文点击与窗口缩放 | 分别以 `swift test --filter <测试名>` 执行 `AttachmentPageStoreTests`、`OrganizationPageStoreTests`、`ComposerTextHitTestingTests` 或 `WindowZoomTests`；宏插件参数同上 |
| 全量编译 | `swift build`，同时编译客户端与 PPT 可执行目标 |
| App 构建与启动 | `./script/build_and_run.sh --verify` |
| 调试启动 | `./script/build_and_run.sh --debug` |

App 构建入口会关闭已运行的 Boxmail；`--verify` 只检查构建和进程存活，不能代替界面及真实服务联调。单独后端启动参数见后端文档。

正式回归测试保留在 `Backend/test/`、`Tests/BoxmailCoreTests/` 和 `Tests/BoxmailTests/`，使用临时目录、模拟 IMAP / AI 和本机 TLS SMTP，不访问真实邮箱、不发送外部邮件、不调用云端 AI。SMTP 测试需要系统 `openssl`。测试应验证数据契约、故障处理或用户行为，避免重复实现细节。

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

`archive-reader.js` 使用精确锁定的 yauzl 3.4.0，通过 `ParserProcess` 读取目录和有界解压，校验实际大小与 CRC；文件从不解压到其提供的路径。`archive-service.js` 负责父附件、内容指纹与包内读取，`archive-analysis.js` 复用普通文件的 `extractText`、`modelFile` 与模型请求，`archive-summary.js` 校验结构化来源。目录、子文件结果和汇总以父附件 ID 独立保存为 archive 记录，附件仅保存 archiveInfo 轻量投影，SQLite 结构版本仍为 2；详情读取再按需组合，备份恢复校验并重建投影。邮件批量任务将 ZIP 作为一项，内部逐文件保存，暂停、重启和重试沿用任务恢复流程。附件列表搜索包含已读取的清单路径与整体分析，不扫描逐文件理解结果。

ZIP 缓存按路径、设备、inode、大小和 mtime／ctime 核对文件身份，稳定命中不重读原包；实际读取包内文件及理解仍使用原始字节。新写入、旧缓存迁移和读取均验证清单，先解码文件名再校验安全路径。备份校验重新派生或移除每份附件的 `archiveInfo`，启动也防护详情缺失；损坏时仅丢弃派生缓存，保留邮件、原附件及有效结果。完整备份从只读 SQLite 快照查询计数和附件 id／name／path，避免水合全部附件与归档详情；恢复前重新派生草稿富文本并清洗转发 HTML。

`AttachmentPreviewLoader` 在后台解码、写入独立临时文件及验证 PDF，界面只接收完成结果，取消和失败都清理文件。普通预览、ZIP 容器和单文件预览分别由独立视图负责。

### 共用列表与分页

`WorkspaceListSurface` 统一圆角、边框和滚动边界：header 与 footer 固定，只有 content 滚动；`WorkspaceList` 在其上提供数据行映射与分隔。附件、分类邮件、分类建议和摘要集合共用这一表面，避免页面外层再套纵向滚动。`SummaryOverviewView` 将流式输出、摘要行和空态放在同一列表视口中，标题、统计和操作固定；账户、列表范围或恢复版本变化时只重建列表，展开及多选不会重置滚动位置。

附件中心通过 `GET /attachments` 每次读取 50 条轻量记录；`attachment-page.js` 在 SQLite 中对当前账户的全部附件进行搜索、类型筛选和排序，只返回当前页及精简原邮件信息，正文、完整分析与 ZIP 目录按需读取。搜索只读取已保存的数据，不触发提取或模型请求。主状态 `/state?compact=1&previews=0` 仍保留全部轻量附件头部，供邮件引用及侧栏计数使用；分页限制的是表格数据和每次列表请求，并未移除全量轻量头部。

`AttachmentPageStore` 管理页码、请求代次、取消、错误重试与数据刷新；条件或账户变化重置页码，附件删除导致越界时服务端回退到末页。`MailStore.workspaceListRevision` 在成功刷新后递增，使当前页重新读取；旧账户、旧条件或已取消请求的响应不能覆盖当前页。附件和智能整理都复用 `WorkspaceList`、`WorkspaceListRow` 与 `ListPagination`；共用组件管理圆角、边框、分隔及行反馈，行区域在内部滚动，表头与分页栏固定，附件视图仅管理列内容、排序和预览/原邮件/下载动作。移除附件专用 Table 外观桥接及重复分页视图；表头与数据行共用计算后的列宽，附件仍每页只渲染 50 条。

智能整理的 `GET /organization/messages` 由 `organization-page.js` 在 SQLite 中按账户、收件箱及分类筛选，稳定按日期倒序 / ID 升序排序，最多返回 100 条（客户端固定 50）。先从已有 message_scope 索引取得计数和当前页 ID，再按 ID 投影当前页头部，避免排序或分组时解析所有正文 JSON。返回 items、total、offset、limit、accountTotal、categoryCounts；正文、HTML 和 AI 分析不进入列表，打开原邮件再读取详情。分类计数覆盖完整收件箱；空分类按“未分类”计算。`OrganizationPageStore` 独立管理取消、旧响应、失败恢复及末页调整，不依赖主状态中的全部邮件头部进行筛选。主状态的轻量缓存用途不变，不能据分页声称 App 只持有 50 封邮件。`OrganizationReviewList` 接收建议、流式输出、页码绑定和邮件操作回调，将流式文字与已完成建议放在同一有界视口内，分页栏固定。分类建议任务本身最多 200 封，UI 在任务已有结果上每页显示 50 条，确认仍应用全部建议。`OrganizeView` 使用固定页面布局，分类邮件与建议分别复用列表内部滚动；分页栏放在对应共用列表的 footer 中，页请求或建议页码变化只重建对应列表，不滚动整页。页面根据可用高度及运行／审阅状态切换紧凑布局：复用相同范围、数量和分类绑定，收紧说明与任务状态，将分类卡片改为原生菜单；窄窗口也保留独立列表视口。

列表状态回归入口为 `Backend/test/attachment-page.test.js`、`organization-page.test.js`、`AttachmentPageStoreTests.swift` 和 `OrganizationPageStoreTests.swift`。布局尺寸和窄窗口规则见 [UI 规范](DESIGN.md#附件中心与资料包)。

### 主窗口缩放

窗口顶部只在两个空白区域使用 `WindowTitlebarRegion`；隐藏标题栏可能先于 NSView 消费双击，因此桥接在挂接时安装局部鼠标监视，仅拦截所属窗口、空白区域内的双击，脱离或销毁时移除；保留搜索框和工具按钮的原生输入。`WindowZoomController` 由 ContentView 持有，按窗口保存缩放前 frame，在当前 NSScreen.visibleFrame 内最大化，第二次恢复；两向均调用 NSWindow.setFrame(_:display:animate:) 的 AppKit 原生动画，不自定义时长或曲线。初始已最大化且没有历史 frame 时，按 MainWindowLayout 的默认 1440 × 900 尺寸生成居中的还原窗口；小屏限制在可用区域的 85%，同时遵守最小尺寸。MainWindowLayout 也为主场景提供默认及最小尺寸，避免两处配置漂移。手动缩放后以新尺寸作为下一次恢复基准，不进入系统全屏。

`WindowZoomTests.swift` 覆盖历史尺寸恢复、初始最大化、边缘误差、小屏、负坐标屏幕及标题区域命中。原生检查同时核对动画、拖动和搜索／按钮输入，验证结果与边界见变更记录。

### 富文本、服务器草稿与会话 AI

0.1.6 实现 A3、A4、A5，0.1.7 完善收件人焦点切换及正文格式。新增字号和颜色使用现有 JSON 记录存储，SQLite `user_version` 仍为 2，旧草稿及备份缺省字段继续兼容。

- 富文本由 `RichTextDocument` 的段落与文字片段表达，`RichTextStyle` 定义字号与不透明 sRGB 颜色，`RichTextController` 负责选区、格式命令和撤销，`RichTextFormatBar` 负责格式控件，`RichTextEditor` 仅桥接 TextKit。文字片段的可选 `fontSize` 使用 pt，范围 8 至 72，最多两位小数；可选 `color` 使用 `#RRGGBB`，省略表示默认 14 pt / `#232D3D`，兼容既有草稿。混合选区提供状态反馈，空选区仅修改输入属性，格式命令保留其他片段属性。后端 `rich-text-style.js` 统一校验和 HTML 样式转换，`rich-text.js` 派生 `bodyHTML` 和纯文本 `body`；同步导入继承并规范化安全的字号、颜色，不保留任意 CSS。编辑器不导入可执行 HTML 或外部资源，保留选区、撤销和中文组合输入。`bodyHTML`、`richText` 与转发快照均从草稿头部及有界搜索投影中剔除。
- `RichTextDocumentProjection` 缓存段落语义，普通输入局部更新；编辑范围有歧义、格式变化或多段编辑时回退完整转换。局部片段到达文末时须与完整转换保持相同的尾部空段落形状；列表标记按内容坐标映射 UTF-16 选区。`RichTextDocumentProjectionTests.swift` 覆盖各位置连续编辑及尾部换行，每步与完整转换比对，继续保留输入法和原生撤销行为。
- `PlainTextEditor.swift` 中的 `PlaceholderTextView` 通过段落间距显示底部签名，布局属性不进入语义正文或保存内容。签名位置每次重算时恢复实际段落元数据，兼容编辑与撤销后的属性变化；普通单击签名前留白时映射到正文末行，点击签名本身仍可编辑，拖选、Shift 选择、非空选区及输入法组合沿用原生行为。`ComposerTextHitTestingTests.swift` 覆盖空正文、短正文、折行、尺寸变化、签名编辑与撤销，以及保存往返。
- `RichTextListLayout` 从每项开头文字派生标记字号、颜色与折行缩进，空白项延续上一行末尾格式；重建和 TextKit 正文变化共用此规则，包含修改字号、继续输入及撤销。标记不进入语义 runs。HTML 在 `li` 上设置标记字号和颜色，并在每个 run 上明确默认样式，避免大字号列表项把原有小字号片段一起放大。
- 草稿随 `syncAccount` 同步，也可限定 `folder=drafts`；复用账户锁、逐条 IMAP 期限、取消和独立 MIME 解析进程。旧版本中只读缓存的服务器草稿迁为可编辑草稿，保留正文和附件。`draft-sync.js` 在 APPEND 前保存随机 MIME token 与内容指纹，重连后核对结果；正文版本与远端 UID / UIDVALIDITY 分开，另以 IMAP 端点及登录身份指纹限制远端绑定与清理，配置改变后保留本机副本待确认。上传返回时重新读取当前草稿，避免覆盖同时发生的编辑、删除和账户切换。
- `DraftSyncIndex` 独立维护轻量匹配字段，跟随 Repository 变更与事务回滚更新，避免逐封全量解析本机草稿。`DraftReadFailures` 按服务器身份、UIDVALIDITY、UID 和大小记录最多 100 个短期失败，60 秒后重试；单封内容异常作为警告继续处理，连接及安全清理错误仍中断当前连接。无法读取的服务器替换版本保留本机内容与远端绑定，不误判为删除。
- `GET /drafts/:id` 及创建回复的响应提供内容修订值 `revision`；客户端保存时回传，旧修订的不同内容返回 409，相同内容重试可安全确认。远端更新保留本机冲突副本，远端删除不直接删除或重新上传本机草稿。删除和发送产生持久化 `draftDeletion` 清理记录；删除意图可按 token／Message-ID 重新对账；连续三轮无法核对后提示人工处理，仍保留记录与备份。执行删除前重新确认目标 UID 与 UIDVALIDITY，且必须支持 UIDPLUS；并发删除后确认目标已不存在则完成清理，目标仍存在则保留意图。
- 富文本正文上限仍为 500,000 字符，链接与文字的累计输入另有 4 MB 上限；服务器草稿 MIME 编码后最多 25 MB，超限留在本机。Boxmail 同步的转发 MIME 使用独立的编辑区与引用区标记，其他安装读取时仍保持快照分离；外部客户端移除标记后按其保存的正文导入。
- `conversation-ai.js` 复用 A1 的同账户引用链，正文按最新优先分配输入预算，再按时间顺序提供模型；最多 50 封、每封 16,000 字符、总计 120,000 字符，并明确部分上下文。输出逐项校验来源 ID，保存会话指纹及来源内容指纹；回复采用时再次核对，关联最新往来。结果仅保存为 Job，单封摘要和已编辑草稿不被覆盖。

相关回归为 `Backend/test/rich-text.test.js`、`draft-sync.test.js`、`conversation-ai.test.js`，以及 Swift 的 `RichTextTests`、`RichTextEditorTests`、`RichTextColorMenuTests` 与草稿加载保护。`WorkflowSelection` 按表单、行内和工具栏三种样式复用原生选择控件；工具栏使用 32 pt 高度、12 pt regular 文字及图标按钮反馈，字号入口宽 64 pt，位于文字颜色之后。`RichTextColorMenu` 通过窄 AppKit 桥接保留原生菜单行为，菜单色样使用非模板 `NSImage`，像素回归核对实际 sRGB 颜色，避免 SwiftUI 菜单符号被统一着色。原生隔离验收已核对格式编辑、保存重开、宽窄布局和依据邮件跳转；实际 IMAP 服务商、其他邮件客户端、真实 AI 服务及 VoiceOver 全流程仍需单独验证。

本次发布的编译、回归与原生验收边界统一记录在变更记录中。

### 邮件字符与数据解码

0.1.4 兼容附件 `contentType` 为 false、空值或无效 MIME 的旧缓存；`mailparser` 对空 `Content-Type:` 会实际返回 false，默认参数只覆盖 undefined，不能修正这类值。`attachment-metadata.js` 统一未知 MIME 类型，Repository 启动只投影检查 MIME 元数据，再分批事务修正异常记录。新写入、完整及紧凑读取、元数据接口和转发副本使用同一规则。

Swift 仅对这项可缺省的描述字段提供回退，附件身份、大小及其他必填字段仍严格验证。修复不触碰附件文件或已有文本、分析；`data.attachment.repaired` 记录字段、实际类型、阶段及匿名记录编号。`attachment-metadata.test.js` 从真实 MIME 复现开始，覆盖持久化、原件一致性、转发及完整备份；Swift HTTP 回归将异常放在第 4,135 个附件，验证 12,001 封邮件的加载、设置保存和退出重启。

本机诊断测试包使用 `./script/build_and_run.sh --package-test`，输出独立 build 目录，保留日常 App 和既有发布包；此模式不创建标签、不推送，不通过正式发布的干净源码检查。交付元数据必须标明工作区快照和基线提交，正式发布仍使用 `package_app.sh` 的干净检出与标签流程。

自 0.1.3 起兼容 JavaScript 字符串截断切开 UTF-16 代理对，以及旧邮件头编码产生未配对代理项时，JSON 响应被 Swift 拒绝的问题。`unicode.js` 在文本片段边界保留完整字符，新记录与 HTTP / SSE 字符串值规范化；旧记录读取时兼容，不批量删除或重建原邮件。有效正文、HTML 和附件字节保持原状，无法表示的孤立代理项以替代字符显示。

`ContentWireIntegrationTests.swift` 启动隔离后端，创建六账户、12,001 封合成邮件，并用真实 MIME 解码产生旧编码异常后直接写入旧记录。通过 HTTP 及 Swift 模型验证首次加载、单封正文、分组查询、设置保存及同目录重启。`unicode-content.test.js` 另检查摘要截断、旧缓存、附件原字节和 SSE；`parser-isolation.test.js` 检查附件驻留内存回收后下一封 MIME 仍可读取。

解码诊断记录 `phase=decode`、精确字段路径、数组下标、期望与实际类型、响应字节数，以及匿名账户和记录编号；未知字典键替换为 `:key`，不写入原始描述和值。`requestID` 关联客户端、HTTP 和同步解析任务；后端在异常字符被替换前记录 `data.unicode.repaired`，包括触发字段和处理阶段。首次问题立即落盘，同一字段和记录的重复问题每 30 秒计数合并，聚合行保留最近请求编号；`diagnostics.dropped` 报告有界写入队列因拥塞省略的条数。

### 品牌图标

原始素材为根目录 `app.png`，客户端品牌资源为 `Sources/BoxmailCore/Resources/BoxmailMark.png`，与原图保持像素一致；图标处理及裁切参数以 `script/generate_icon.swift` 为准。客户端通过 `BoxmailBrand` 读取资源并缓存图片，侧栏按 28 pt 显示。

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
| 写信 | 空收件人／抄送／密送的鼠标与 Tab 切换、关键词联系人浮层、中文输入法、键盘和跨字段去重、字号与颜色、列表标记继承及撤销、聚焦下划线、签名置底、正文空白点击定位及签名编辑撤销、粘贴文件及图片、草稿恢复 |
| 附件中心与 ZIP | 50 条分页、首尾页与越界回退、跨页搜索与全局排序、条件和账户切换、错误重试、侧栏顺序、表头与操作对齐、浅蓝选中底、包内预览、逐文件理解、暂停继续及来源跳转 |
| 智能整理 | 全收件箱分类计数、50 封分页、切换分类与账户、迟到响应及失败恢复、建议翻页与整批确认 |
| AI | 总结、三种回复态度、显式使用和草稿复用、翻译持久化、批量附件暂停与失败恢复、分类确认与撤销 |
| 搜索 | 中文、附件内容、组合条件、跨账户、草稿编辑身份、日期边界、闰年及翻月后保留条件 |
| 设置与数据 | 模型列表重启和失败保留、配置合并及凭证引用、跨目录完整备份恢复、原排版译文及总结收录状态、附件字节与重启、校验及回滚、目录迁移和外置盘缺失 |
| 布局与预览 | 顶部双击的原生最大化／还原动画、初始最大化默认还原、小屏及多屏、宽窄窗口、294 pt 邮件栏、四项筛选、紧凑列表、原生多选、快捷键与撤销、年月菜单、PDF / Word / XLSX / PPT 原文件及无轨道滚动条 |
| 生命周期 | 退出时子进程和文件锁释放、任务中断状态、再次启动后的数据和凭证行为 |

结果不确定的发送先核对实际投递，不能自动重试；永久清空只在明确可丢弃的测试邮箱中执行。新增操作保留现有发送确认、分类审阅和撤销机制。

隔离原生验收可执行 `env -u BOXMAIL_ENV_FILE BOXMAIL_DATA="$(mktemp -d /tmp/boxmail-review.XXXXXX)" ./script/build_and_run.sh --review`。此模式使用 `com.boxmail.desktop.review`、独立进程名称 `Boxmail Review` 和 `artifacts/ui-review/Boxmail Review.app`，便于自动化准确选择实例，不关闭日常 App；数据目录必填，默认凭证文件也与日常 App 分离。日常开发版与发布包默认关闭演示数据初始化，只有隔离验收模式启用；关闭初始化不会清理已有数据。只在合成数据中验证批量删除和撤销。

原生验收覆盖账户切换、列表选择、原邮件跳转、会话、未读筛选、归档和撤销、草稿恢复、HTML 转发、译文切换及原文件预览。无障碍名称通过 AX 树检查；VoiceOver 全流程、真实外部投递及其他服务商不属于本机合成回归的验证结论。

### 后端生命周期

`BoxmailCore.LocalBackendProcess` 持有进程及数据目录锁，启动后关闭父进程中用于 stdin 继承的重复文件描述符，避免已结束的子进程仍通过本地引用占锁。App 退出先取消客户端任务，再等待后端关闭；服务的清理期限为 3 秒，App 在 4 秒后仍未等到退出时只终止自己创建的子进程，确认退出后才释放租约。

`Backend/src/service-lifecycle.js` 在数据库初始化前安装退出处理，检查父进程并通过 stdout 管道检测 App 消失。已有旧服务占锁时，客户端仅回收同用户、同一运行时路径、stdin 指向同一锁文件且父进程已为 1 的孤立后端；其他活跃 App 和无关 Node 进程继续保留。就绪检查使用 `/health`，完整状态另按需读取。

### 界面约定

完整的颜色、字体、尺寸、共用组件、交互状态、动效与界面验收要求见 [UI 规范](DESIGN.md)。本节保留操作语义和实现约定；修改共用界面规则时同步更新规范与对应源码。

- 系统字体、SF Symbols、蓝色强调；次要操作采用无描边图标文字，键盘焦点用细下划线，写邮件入口及选中筛选使用浅蓝底。
- 设置按常用、账号、AI 助手、高级和开发者分组；宽度不足 900 pt 时用顶部分类标签替代左导航。五类共用“取消／保存”底栏，保存成功后关闭，失败保留当前输入和错误。账号编辑拥有独立保存／取消窗口，移除操作位于更多菜单。模型连接细节与目录按需展开，任务提示词独立切换。设置和写信面板尺寸跟随主窗口可用空间。
- 设置及账号、服务商、模型、配置导入面板共用 SettingsActionBar，底栏高 64 pt、按钮高 34 pt、连续圆角 10 pt；取消使用浅色边框，主操作使用纯蓝底色。悬停、按下、键盘焦点和禁用状态由同一按钮样式处理，保留 Escape 与默认动作快捷键。
- 设置表单共用 34 pt 控件高度、88 pt 标签列与 280 pt 常规字段宽度；名称、地址、密钥、模型和推理映射按同一字段列对齐，操作紧邻字段。超时、端口及数值容量保留短数值框，签名与提示词保留多行编辑区。添加、测试和获取等文字操作使用蓝色强调，控件图标使用统一槽位和文字基线。
- 设置中的折叠分组共用 SettingsDisclosureStyle，标题、箭头与右侧留白组成整行按钮，高度至少 36 pt，统一悬停和键盘焦点反馈；无障碍值说明已展开或已收起。
- Logo 位于全高侧栏的窗口按钮下方，写邮件固定在其下；主窗口最小 720 × 600 pt，宽度不足 1080 pt 时侧栏改为导航浮层；邮件栏允许 294 至 560 pt 拖动调整，聚合展开槽位压缩但保持行文本对齐。邮件四项筛选高 32 pt、间距 6 pt，窄分栏仍完整显示。邮件行使用三层文字与单行预览，多选时原位替换筛选为批量操作，阅读区的邮件操作栏高 44 pt，AI 总结、翻译和 AI 回复以独立按钮平铺在其下方的 36 pt 操作栏；附件理解只在附件区域显示；分页跟随列表滚动，缓存计数收进同步详情。
- 收件箱使用原生 List 的连续／离散选择与方向键导航。邮件快捷键通过 FocusedValue 限定在列表；文字输入继续使用编辑器按键。手动单封与批量操作共用 /messages/batch，在事务中提交，UndoManager 注册最近一次操作；自动标记已读不占用手动撤销记录。撤销带 expected 字段，遇到后续冲突整体拒绝，避免覆盖其他操作。备份恢复后清除旧撤销与选择。
- List 的 Binding 只提交当前查询的用户选择，程序跳转和列表刷新直接协调状态，不再通过选择变化观察器反向触发点击。目标列表未载入时保留 openMail 指定的邮件与 AI 面板；分页响应按返回时的当前选择处理，过期查询和列表回调直接丢弃。openMail 每次生成独立 MailRevealRequest，目标行就绪后由 ScrollViewReader 滚动至可见位置并消费该请求；重复打开、页外目标及用户后续选择分别处理，普通刷新不反复抢回滚动位置。
- 邮件行的可访问名称包含已读状态、日期、附件数量、星标、总结与分类；预览作为提示，原生列表负责宣布选中状态。图标菜单用带文字的原生 Label 提供名称，避免只宣布符号含义。
- 下拉菜单保留原生菜单跟踪、键盘与无障碍操作；按钮和输入框共用 34 pt 高度、10 pt 圆角、浅色边框和蓝色焦点轮廓。筛选、侧栏选中底色使用 12 pt 连续圆角，紧凑筛选使用 10 pt；AI 分区切换使用浅底槽和白色选中面板。长值可悬停查看，选择变化不应挤动输入列。
- 日期面板宽 360 pt，年月分配独立槽位、组间距 24 pt，文字和箭头整体居中；翻月、菜单及回填保持原生操作。
- 普通滚动区域沿用无描边浮层细滑块。长收件人名单显式保留原生滚动条，溢出时持续可见，全局外观刷新不会重新隐藏它。MailBodyWebView 根据受信任脚本报告的收件人区域绘制独立 NSScroller，并将位置变化传回隔离客户端世界；切换文档清理旧滚动条。引用标题单独约束不换行与顶部对齐，原 HTML 和邮件脚本、联网限制不变。
- HTML 转发草稿以 forwardedHTML / forwardedText 保存原文快照，body 仅保存可编辑说明和签名；旧的完整未编辑引用在展示或保存时恢复快照，已编辑引用保持原样。发送合并 HTML 与纯文本，并将 data 图片转换为 CID MIME 资源；本机已发送副本保留可独立阅读的原 HTML。草稿搜索、备份和重开保留快照，无需原邮件仍在。
- 写信默认收起空白抄送和密送，已有地址的字段保持可见；AI 助手按需展开，窄面板使用浮层。未编辑的新邮件关闭不落盘为空草稿。联系人浮层不改变字段与正文坐标；短正文签名置底的留白不写入邮件。`PlaceholderTextView` 根据签名实际显示位置校正插入点，原生鼠标跟踪完成后，将签名前留白中的普通单击定位到正文末行；非空选区、拖选和 Shift 选择继续由原生处理。直接点击签名仍正常编辑，撤销恢复的布局属性会先还原再计算置底间距。正文、提示词和签名编辑器保留输入法、撤销及 Binding。
- `RecipientEntryView` 的 AppKit 输入仅在 `isEnabled` 真正变化时赋值，避免焦点刷新重复触发系统自动填充空面板。空关键词不打开联系人建议；输入、中文组合、鼠标和 Tab 焦点交接保持原生行为。`RecipientEntryTests.swift` 通过真实共享编辑器和 KVO 检查空框切换不重复通知，同时验证真正的启用和禁用仍传到每个输入框。
- AI 生成内容经认证的 `/ai/events` SSE 逐步显示，共用 Markdown 组件；中间预览不写入数据库，完整校验后才提交。断线重连先接收活动快照，结束及退出时清理连接；分类确认、草稿使用等操作等待完整结果。
- 翻译通过原邮件文字节点 ID 对齐，后端只替换文字并转义模型内容；保留代码、链接属性、图片及样式。`translation` 继续用于搜索与复制，`translationHTML` 保存原排版译文，紧凑列表不含这两个正文大字段。WebKit 在隔离客户端世界更新文本节点，邮件脚本和联网限制继续生效。
- 完成后的 AI 结果标题整行可展开、复制独立；阅读区摘要按宽度在三列、两列与纵向间切换，长待办和期限自然换行，关键信息默认展开；摘要集合使用概要、最多两项未完成待办和按项展开的详情，展开后关键信息仍可单独打开。
- 顶部搜索始终以“邮件搜索”标明范围，侧栏不继续高亮原页面；返回入口清除搜索。辅助工作区在搜索期间保留视图身份与局部筛选，避免返回后丢失附件搜索、类型或滚动位置。附件空态区分无数据与筛选无结果，后者提供清除筛选。
- 摘要列表使用邮件元数据 `summaryHidden` 记录收录状态，缺省为收录；移除、多选和清空仅更新此标记，不删除 `summary`。状态按账户隔离并随同步和完整备份保留，重新生成总结时重新收录。列表、已移除和撤销共用 `/summaries/visibility`；侧栏“摘要集合”计数按收录项计算，单封总结直接从“AI 总结”按钮进入，邮件的“AI 已总结”标签及筛选仍按实际总结判断。
- 设置导航、参数展开和摘要列表增减使用短状态过渡，不为逐个流式字符添加布局动画；系统减少动态效果时关闭位移及展开动画，保留必要状态反馈。
- 动效跟随系统“减少动态效果”；界面维护以 UI 规范及其关联的 SwiftUI／AppKit 源码为准。

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

普通修复及文档整理可保持版本号和构建号，在 [CHANGELOG](../CHANGELOG.md) 的“未发布”中记录。正式发布时同步更新：

| 文件 | 内容 |
| --- | --- |
| `VERSION` | App 版本来源 |
| `Backend/package.json`、`Backend/package-lock.json` | 后端包版本，可用 `npm version <版本> --prefix Backend --no-git-tag-version` |
| `BUILD` | 构建号来源，构建脚本校验并写入 `CFBundleVersion`；打包读取同次构建的 Info.plist |
| `CHANGELOG.md`、`README.md` | 发布日期、变化、验证范围及当前版本 |
| `docs/USER_GUIDE.md`、`docs/DESIGN.md`、`docs/DEVELOPMENT.md`、`docs/ROADMAP.md`、`Backend/README.md` | 适用版本、当前操作、UI 规范、接口契约、回归基线及已发布范围 |

1. 完成适用的回归、编译和原生联调，检查差异，不提交个人数据。
2. 提交源码和文档后建立 `v<版本>` 标签，从干净标签或独立检出执行 `./script/package_app.sh`。脚本拒绝未提交及未跟踪的源码修改。
3. 核对版本、构建号、内置资源、Node.js 及原生依赖、嵌套签名、包内说明、源码标签和完整提交号。
4. 校验 ZIP 的 SHA-256、解压一致性及签名，并用独立空目录检查首次启动。最低系统、其他架构和设备需分别验证。
5. 推送发布提交和新标签至 GitHub，在对应标签的 Release 上传 ZIP 与 SHA-256 文件，并核对远端提交、资产大小和校验值。

发布模式用 Release 构建，只复制后端源码及生产依赖，关闭演示数据，不关闭或启动日常 App。`docs/USER_GUIDE.md` 复制为包内`使用说明.md`，因此保持指南可独立阅读，不依赖仓库内链接。`版本信息.txt`记录版本、源码标识和上海时区生成时间。产物在 `dist/`，日常 App 为 `dist/Boxmail.app`。

已发布标签保持不动，同版本重打包使用新的 `v<版本>-repack.N` 标签。GitHub Release 按版本发布安装包；历史版本及源码可通过 Release、Git 提交与标签追溯。

## 文档与本地产物

产品文档以项目入口、使用指南、UI 规范、开发说明、后端接口、开发路线和变更记录为主。操作与限制更新到对应指南，审查修复结论及验证范围合并到 CHANGELOG，避免另存过时的源码行号、重复发布状态和一次性验收报告。发件人聚合与开发者设置的稳定界面约定已合并到本文，已移除的协作文档、诊断记录和界面快照不再作为当前约定来源。未发布变化明确标为当前源码或日常开发版，不改写历史发布版本的功能与测试基线；删除文档时同步移除或替换引用。

`.build/`、`dist/`、`Backend/node_modules/`、`artifacts/`、`.scratch/`、`.impeccable/critique/`、数据库、日志、环境变量及签名配置均不提交 Git；Impeccable 的项目配置保留在 `.impeccable/config.json`。临时测试 App、构建副本、探针、基准 JSON 和合成数据完成验证后可清理；正式回归、附件样例和可复现的性能脚本保留。真实数据的安全备份与测试结果分开管理，不随报告清理。历史发布日志和截图可留在 `artifacts/release-*/` 等本机目录，不作为运行依赖。

当前本机测试与历史原生验收不能代替真实外部投递、其他邮件或 AI 服务商、大邮箱性能、最低系统、Intel、屏幕阅读器及正式分发验证。具体发布时的范围保留在 CHANGELOG。
