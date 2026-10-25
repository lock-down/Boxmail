# 开发与维护

项目启动及文档入口见 [README](../README.md)，操作行为见 [使用指南](USER_GUIDE.md)，路由和数据契约见 [后端接口](../Backend/README.md)。日常开发保持 SwiftUI、本机 Node.js 和 SQLite 的结构。

## 源码入口

| 目录或模块 | 职责 |
| --- | --- |
| `Sources/Boxmail/App/` | 应用、场景和命令 |
| `Sources/Boxmail/Views/` | 邮件、写信、搜索、附件和设置界面 |
| `Sources/Boxmail/Support/` | 设计系统、动效、滚动及原生预览桥接 |
| `Sources/Boxmail/Stores/MailStore.swift` 及扩展 | 状态、后端调用、分页、缓存、AI 输出流和任务轮询 |
| `Sources/Boxmail/Services/` | 后端生命周期、钥匙串和配置迁移 |
| `Sources/BoxmailCore/` | 数据模型、配置归档、存储迁移、后端进程与目录锁、文本与日期逻辑 |
| `Sources/BoxmailCore/Resources/` | 共享提示词、回复态度、收件人布局及客户端品牌图片 |
| `Tests/BoxmailTests/` | 直接验证客户端 MailStore 的导航、列表选择与分页响应状态 |
| `Sources/BoxmailPresentationRenderer/` | WebKit / PDFKit 幻灯片页面生成 |
| `Backend/src/` | 协议、HTTP、任务、持久化、索引及备份 |

修改接口时同步检查 Swift 模型、后端路由和调用方；修改数据结构需设计迁移和旧数据兼容。应用版本与 SQLite 结构版本独立，当前 `user_version=2`，搜索索引为可重建派生数据。

## 构建与测试

在仓库根目录执行，依赖及工具链要求见 README。

```bash
./script/test.sh
git diff --check
```

`test.sh` 先构建 `BoxmailPresentationRenderer`，通过 `BOXMAIL_PRESENTATION_RENDERER` 传给后端测试，再运行 Node.js 和 Swift 测试。工具链提供 `TestingMacros` 插件时显式加载，避免部分 Command Line Tools 未自动加载宏的问题。

0.1.0 完整回归通过 325 项后端测试、103 项 Swift 测试，无失败或跳过。覆盖邮件与附件提交故障、同 ID 备份恢复预览、磁盘容量不足、WAL 强制退出恢复、IMAP 期限与取消、PPT 解析取消、JSON 主线程隔离及客户端旧响应竞态；大邮箱用例一次补齐 12073 封收件箱与 543 封已发送。原生 AppKit / WebKit 测试检查列表定位、选择与分页、长收件人滚动条、转发预览和标题横排。发布时另验证正式包的图标、徽标、资源、签名、首次启动及退出清理。

| 需要验证的范围 | 命令 |
| --- | --- |
| 完整回归 | `./script/test.sh` |
| 正文同步与大邮箱回归 | `cd Backend` 后执行 `node --test test/sync-source.test.js test/sync-reliability.test.js test/sync-inventory.test.js test/sync-session.test.js` |
| 单个后端模块 | `cd Backend` 后执行 `node --test test/configuration.test.js`，按模块替换文件名 |
| Swift 核心逻辑 | `swift test`；若宏插件未加载，使用测试脚本中的插件参数 |
| 客户端导航与选择 | `swift test --filter BoxmailTests`；宏插件参数同上 |
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
| `node script/benchmark.mjs` | 默认 2400 封合成邮件、四个账户；检查索引、联系人、会话、分页、无变化同步和重复下载 |
| `node script/benchmark-startup.mjs` | 三个独立后端进程；测量模块载入、元数据、首屏、详情及会话就绪时间与 RSS |
| `node script/benchmark-runtime.mjs` | 缓存追加同步、12 个流式 AI 任务、三次 20 MB 图片上传和三次 20 页 PDF 分析 |
| `BOXMAIL_BENCHMARK_ROUNDS=40 node --expose-gc script/benchmark-runtime.mjs ai` | 120 个连续 AI 任务，检查任务完成、保存结果、流式输出及 GC 前后资源 |

基准在临时目录生成数据，只使用本机模拟服务，不读取日常 App 数据或钥匙串。查询取多次中位数，启动使用独立进程，运行时模式分别建立新进程。比较版本时使用相同 Node.js、数据规模和脚本，串行运行，避免与构建或测试争用 CPU。

后端 RSS 和 HTTP 就绪时间不包含客户端、WebKit、系统冷启动与真实网络；GC 后的 JS 堆也不等于操作系统已回收内存，短期测试不能证明长期无泄漏。原生验收需单独记录客户端、后端及 WebKit 的测量范围。原始 JSON、截图和日志保存在本机 `artifacts/`。

### 品牌图标

原始素材为根目录 `app.png`，客户端品牌资源为 `Sources/BoxmailCore/Resources/BoxmailMark.png`，与原图保持像素一致，处理来源与裁切参数保存在 `Design/Brand/BoxmailMark.json`。客户端通过 `BoxmailBrand` 读取资源并缓存图片，侧栏按 28 pt 显示。

`script/generate_icon.swift` 从同一原始图片生成 16、32、64、128、256、512 和 1024 像素的标准 iconset；裁切原图外围 5% 并施加圆角遮罩，统一主体尺寸和透明留白，再由 `iconutil` 转为 `Boxmail.icns`。构建脚本在图片或生成脚本变更时重建图标，App 启动时使用包内图标更新 Dock 与“关于”窗口。更换品牌素材后检查浅色与深色背景、小尺寸可辨识性、侧栏及实际安装包，避免只替换源码中的图片。

### 代码与异步状态约定

- Swift 和 JavaScript 使用两空格缩进；Swift 修改范围使用工具链自带的 `swift-format` 整理，保留未修改代码的现有布局。
- `MailStore` 保持主线程状态隔离，调用统一的后端实例；HTTP 请求序列化、响应及 SSE 解码在主线程之外执行，完整结果回到主线程后再更新观察状态。
- 元数据、列表、详情及会话响应按各自请求版本检查；恢复完成后、刷新前递增数据恢复版本，忽略旧数据库的在途结果。附件缓存仅接收当前邮件、展开会话或仍打开预览所需的内容。
- SQLite 事务只执行同步记录操作；先准备附件文件，再将邮件、附件及关联引用一并提交，失败清理本次准备的文件。恢复成功后同时重建索引并使邮件预览缓存失效。
- IMAP 待提交操作复用逐条命令期限与取消处理，失败保留待同步更改；不以整批总时长替代单条命令期限。

## 联调与界面检查

使用独立测试账号、收件人、数据目录和合成附件。原生验收副本使用独立 Bundle ID，钥匙串服务名自动取 `<Bundle ID>.credentials`；正式 App 仍为 `com.boxmail.desktop.credentials`。App 可通过绝对路径 `BOXMAIL_DATA` 使用临时目录，不改变日常数据位置；不要与正在运行的 App 共用后端目录。

| 流程 | 检查重点 |
| --- | --- |
| 账户与同步 | 两种 TLS、默认与自定义端口、认证错误、千封历史回填、断网及重启、UIDVALIDITY 和跨账户隔离 |
| 阅读与会话 | HTML / CID / 远程图片开关、时间线及引用折叠、逐封回复和原身份、恢复及取消归档的来源 |
| 写信 | 关键词联系人浮层、中文输入法、键盘和跨字段去重、聚焦下划线、签名置底、粘贴文件及图片、草稿恢复 |
| AI | 总结、三种回复态度、显式使用和草稿复用、翻译持久化、批量附件暂停与失败恢复、分类确认与撤销 |
| 搜索 | 中文、附件内容、组合条件、跨账户、草稿编辑身份、日期边界、闰年及翻月后保留条件 |
| 设置与数据 | 模型列表重启和失败保留、配置合并及凭证引用、跨目录完整备份恢复、原排版译文及总结收录状态、附件字节与重启、校验及回滚、目录迁移和外置盘缺失 |
| 布局与预览 | 宽窄窗口、294 pt 邮件栏、四项筛选、紧凑列表、原生多选、快捷键与撤销、年月菜单、PDF / Word / XLSX / PPT 原文件及无轨道滚动条 |
| 生命周期 | 退出时子进程和文件锁释放、任务中断状态、再次启动后的数据和凭证行为 |

结果不确定的发送先核对实际投递，不能自动重试；永久清空只在明确可丢弃的测试邮箱中执行。新增操作保留现有发送确认、分类审阅和撤销机制。

隔离原生验收可执行 `BOXMAIL_DATA="$(mktemp -d /tmp/boxmail-review.XXXXXX)" ./script/build_and_run.sh --review`。此模式使用 `com.boxmail.desktop.review` 和 `artifacts/ui-review/Boxmail Review.app`，不关闭日常 App；数据目录必填，钥匙串服务与正式 App 分离。只在合成数据中验证批量删除和撤销。

原生验收覆盖账户切换、列表选择、原邮件跳转、会话、未读筛选、归档和撤销、草稿恢复、HTML 转发、译文切换及原文件预览。无障碍名称通过 AX 树检查；VoiceOver 全流程、真实外部投递及其他服务商不属于本机合成回归的验证结论。

### 后端生命周期

`BoxmailCore.LocalBackendProcess` 持有进程及数据目录锁，启动后关闭父进程中用于 stdin 继承的重复文件描述符，避免已结束的子进程仍通过本地引用占锁。App 退出先取消客户端任务，再等待后端关闭；服务的清理期限为 3 秒，App 在 4 秒后仍未等到退出时只终止自己创建的子进程，确认退出后才释放租约。

`Backend/src/service-lifecycle.js` 在数据库初始化前安装退出处理，检查父进程并通过 stdout 管道检测 App 消失。已有旧服务占锁时，客户端仅回收同用户、同一运行时路径、stdin 指向同一锁文件且父进程已为 1 的孤立后端；其他活跃 App 和无关 Node 进程继续保留。就绪检查使用 `/health`，完整状态另按需读取。

### 界面约定

- 系统字体、SF Symbols、蓝色强调；次要操作采用无描边图标文字，键盘焦点用细下划线，写邮件入口及选中筛选使用浅蓝底。
- 设置表单共用 34 pt 控件高度和固定标签列，名称、地址、密钥按内容约束宽度；操作列与字段紧邻，添加、测试和获取等文字操作使用蓝色强调。签名编辑区保持紧凑并支持内部滚动，控件图标使用统一槽位和文字基线。
- Logo 位于全高侧栏的窗口按钮下方，写邮件固定在其下；邮件四项筛选高 32 pt、间距 6 pt，窄分栏仍完整显示。邮件行使用三层文字与单行预览，多选时原位替换筛选为批量操作，阅读区的邮件操作栏高 44 pt，AI 总结、翻译和 AI 回复以独立按钮平铺在其下方的 36 pt 操作栏；附件理解只在附件区域显示；分页跟随列表滚动，缓存计数收进同步详情。
- 收件箱使用原生 List 的连续／离散选择与方向键导航。邮件快捷键通过 FocusedValue 限定在列表；文字输入继续使用编辑器按键。手动单封与批量操作共用 /messages/batch，在事务中提交，UndoManager 注册最近一次操作；自动标记已读不占用手动撤销记录。撤销带 expected 字段，遇到后续冲突整体拒绝，避免覆盖其他操作。备份恢复后清除旧撤销与选择。
- List 的 Binding 只提交当前查询的用户选择，程序跳转和列表刷新直接协调状态，不再通过选择变化观察器反向触发点击。目标列表未载入时保留 openMail 指定的邮件与 AI 面板；分页响应按返回时的当前选择处理，过期查询和列表回调直接丢弃。openMail 每次生成独立 MailRevealRequest，目标行就绪后由 ScrollViewReader 滚动至可见位置并消费该请求；重复打开、页外目标及用户后续选择分别处理，普通刷新不反复抢回滚动位置。
- 邮件行的可访问名称包含已读状态、日期、附件数量、星标、总结与分类；预览作为提示，原生列表负责宣布选中状态。图标菜单用带文字的原生 Label 提供名称，避免只宣布符号含义。
- 菜单沿用紧凑原生选择，长值可悬停查看；账号与 AI 表单标签左对齐，选择变化不应挤动输入列。
- 日期面板宽 360 pt，年月分配独立槽位、组间距 24 pt，文字和箭头整体居中；翻月、菜单及回填保持原生操作。
- 普通滚动区域沿用无描边浮层细滑块。长收件人名单显式保留原生滚动条，溢出时持续可见，全局外观刷新不会重新隐藏它。MailBodyWebView 根据受信任脚本报告的收件人区域绘制独立 NSScroller，并将位置变化传回隔离客户端世界；切换文档清理旧滚动条。引用标题单独约束不换行与顶部对齐，原 HTML 和邮件脚本、联网限制不变。
- HTML 转发草稿以 forwardedHTML / forwardedText 保存原文快照，body 仅保存可编辑说明和签名；旧的完整未编辑引用在展示或保存时恢复快照，已编辑引用保持原样。发送合并 HTML 与纯文本，并将 data 图片转换为 CID MIME 资源；本机已发送副本保留可独立阅读的原 HTML。草稿搜索、备份和重开保留快照，无需原邮件仍在。
- 联系人浮层不改变字段与正文坐标；短正文签名置底的留白不写入邮件。正文、提示词和签名编辑器保留输入法、撤销及 Binding。
- AI 生成内容经认证的 `/ai/events` SSE 逐步显示，共用 Markdown 组件；中间预览不写入数据库，完整校验后才提交。断线重连先接收活动快照，结束及退出时清理连接；分类确认、草稿使用等操作等待完整结果。
- 翻译通过原邮件文字节点 ID 对齐，后端只替换文字并转义模型内容；保留代码、链接属性、图片及样式。`translation` 继续用于搜索与复制，`translationHTML` 保存原排版译文，紧凑列表不含这两个正文大字段。WebKit 在隔离客户端世界更新文本节点，邮件脚本和联网限制继续生效。
- 完成后的 AI 结果标题整行可展开、复制独立；摘要按宽度在三列、两列与纵向间切换，长待办和期限自然换行，关键信息默认展开。
- 摘要列表使用邮件元数据 `summaryHidden` 记录收录状态，缺省为收录；移除、多选和清空仅更新此标记，不删除 `summary`。状态按账户隔离并随同步和完整备份保留，重新生成总结时重新收录。列表、已移除和撤销共用 `/summaries/visibility`；侧栏“摘要集合”计数按收录项计算，单封总结直接从“AI 总结”按钮进入，邮件的“AI 已总结”标签及筛选仍按实际总结判断。
- 设置导航、参数展开和摘要列表增减使用短状态过渡，不为逐个流式字符添加布局动画；系统减少动态效果时关闭位移及展开动画，保留必要状态反馈。
- 动效跟随系统“减少动态效果”；设计参考保留 `Design/Exports/` 的 19 个 HTML/CSS，App 不直接运行它们。

## 钥匙串与签名

凭证在钥匙串保存，进程内缓存成功读取的结果，退出清空。后台只使用已授权缓存；普通偏好保存不得清空尚未读取的 API Key。配置导入先写新凭证项，再事务提交引用；失败保留旧配置，密钥不进入 SQLite。

默认 `codesign --sign -` 临时签名的指定要求依赖代码哈希，重编译后可能再次请求授权；固定 Bundle ID 不足以解决。使用带私钥的固定签名证书时：

```bash
security find-identity -v -p codesigning
BOXMAIL_SIGNING_IDENTITY="证书的 SHA-1 指纹" ./script/build_and_run.sh --verify
codesign -dvvv -r- dist/Boxmail.app
codesign --verify --deep --strict dist/Boxmail.app
```

也可将指纹单独写入根目录 `.boxmail-signing-identity`，该文件已忽略；环境变量优先。固定证书下跨重编译保留授权尚未实测，正式签名和公证需另行验证。

## 版本与打包

普通修复及文档整理可保持版本号和构建号，在 [CHANGELOG](../CHANGELOG.md) 的“未发布”中记录。正式发布时同步更新：

| 文件 | 内容 |
| --- | --- |
| `VERSION` | App 版本来源 |
| `Backend/package.json`、`Backend/package-lock.json` | 后端包版本，可用 `npm version <版本> --prefix Backend --no-git-tag-version` |
| `script/build_and_run.sh` | 递增 `CFBundleVersion` |
| `CHANGELOG.md`、`README.md` | 发布日期、变化、验证范围及当前版本 |
| `docs/USER_GUIDE.md`、`docs/DEVELOPMENT.md`、`docs/ROADMAP.md`、`Backend/README.md` | 适用版本、当前操作、接口契约、回归基线及已发布范围 |

1. 完成适用的回归、编译和原生联调，检查差异，不提交个人数据。
2. 提交源码和文档后建立 `v<版本>` 标签，从干净标签或独立检出执行 `./script/package_app.sh`。脚本拒绝未提交及未跟踪的源码修改。
3. 核对版本、构建号、内置资源、Node.js 及原生依赖、嵌套签名、包内说明、源码标签和完整提交号。
4. 校验 ZIP 的 SHA-256、解压一致性及签名，并用独立空目录检查首次启动。最低系统、其他架构和设备需分别验证。
5. 推送发布提交和新标签至 GitHub，在对应标签的 Release 上传 ZIP 与 SHA-256 文件，并核对远端提交、资产大小和校验值。

发布模式用 Release 构建，只复制后端源码及生产依赖，关闭演示数据，不关闭或启动日常 App。`docs/USER_GUIDE.md` 复制为包内`使用说明.md`，因此保持指南可独立阅读，不依赖仓库内链接。`版本信息.txt`记录版本、源码标识和上海时区生成时间。产物在 `dist/`，日常 App 为 `dist/Boxmail.app`。

已发布标签保持不动，同版本重打包使用新的 `v<版本>-repack.N` 标签。GitHub Release 以 0.1.0 作为对外基线；清理旧发布条目不改写 Git 历史，历史实现仍可通过提交与标签追溯。

## 文档与本地产物

文档只保留项目入口、使用指南、开发说明、后端接口、开发路线和变更记录。操作与限制更新到对应指南，CHANGELOG 记录合并后的发布基线；过时的源码行号、重复发布状态和一次性验收过程不再单独成文。

`.build/`、`dist/`、`Backend/node_modules/`、`artifacts/`、`.scratch/`、`.impeccable/critique/`、数据库、日志、环境变量及签名配置均不提交 Git；Impeccable 的项目配置保留在 `.impeccable/config.json`。临时测试 App、构建副本、探针和合成数据完成验证后可清理；正式回归及其附件样例保留。历史发布日志和截图可留在 `artifacts/release-*/` 等本机目录，不作为运行依赖。

当前本机测试与历史原生验收不能代替真实外部投递、其他邮件或 AI 服务商、大邮箱性能、最低系统、Intel、屏幕阅读器及正式分发验证。具体发布时的范围保留在 CHANGELOG。
