---
name: Boxmail UI
description: 原生 macOS 邮件工作台的现行界面规范，尺寸使用 SwiftUI 逻辑点。
colors:
  blue: "#3567AF"
  blue-soft: "#EBF1FA"
  chrome: "#F8F9FB"
  sidebar: "#F3F5F8"
  canvas: "#F7F8FA"
  paper: "#FFFFFF"
  border: "#D8DFE8"
  soft-border: "#E9EDF2"
  ink: "#232D3D"
  muted: "#606E82"
  success: "#28745B"
  amber: "#98651F"
typography:
  title: { fontFamily: "system", fontSize: "24pt", fontWeight: 600 }
  heading: { fontFamily: "system", fontSize: "17pt", fontWeight: 600 }
  section: { fontFamily: "system", fontSize: "14pt", fontWeight: 600 }
  body: { fontFamily: "system", fontSize: "13pt", fontWeight: 400 }
  caption: { fontFamily: "system", fontSize: "12pt", fontWeight: 400 }
  small: { fontFamily: "system", fontSize: "11pt", fontWeight: 400 }
rounded:
  surface: "12pt"
  control: "10pt"
  selection: "12pt"
spacing:
  page-inset: "28pt"
  settings-inset: "24pt"
  section-inset: "20pt"
  section-content-gap: "16pt"
  form-column-gap: "12pt"
  filter-gap: "6pt"
components:
  settings-action-primary:
    backgroundColor: "{colors.blue}"
    textColor: "{colors.paper}"
    rounded: "{rounded.control}"
    padding: "0 16pt"
  settings-text-input:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink}"
    rounded: "{rounded.control}"
    height: "34pt"
    padding: "0 10pt"
  filter-bar-selected:
    backgroundColor: "{colors.blue-soft}"
    textColor: "{colors.blue}"
    rounded: "{rounded.selection}"
    height: "32pt"
    padding: "0 10pt"
  section-card:
    backgroundColor: "{colors.paper}"
    rounded: "{rounded.surface}"
    padding: "20pt"
---

# Boxmail UI 规范

## Overview

### 定位与适用范围

Boxmail 是原生 macOS AI 邮件客户端。界面围绕查找、阅读、撰写和处理邮件组织，采用紧凑列表、清楚的内容层级、系统字体和蓝灰配色。AI 能力放在邮件及附件的操作上下文中。

本规范于 2026-11-09 从现有 SwiftUI / AppKit 实现及开发说明整理，用于新增界面、维护共用组件和界面验收。风格描述是对现有实现的归纳。当前主窗口与系统设置场景固定使用浅色外观；深色主题尚未建立对应的颜色与组件规范。

适用版本为 Boxmail 0.1.6（build 45），包含富文本格式栏、服务器草稿同步状态和会话 AI 的界面约定。

本文数值均为原生界面的逻辑点（pt），不按截图像素换算。邮件 HTML 正文使用 WebKit 的 CSS 单位，单独遵循正文规则。顶部 YAML 提供可读取的现有设计值；`system` 表示系统字体，不指定字体文件。运行时仍由下表中的 Swift 常量和组件实现提供样式；修改共用设计值时应同步更新源码与本文。

### 依据与维护入口

| 范围 | 实现依据 |
| --- | --- |
| 颜色、字体、基础尺寸、按钮、标签、卡片、空态 | [DesignSystem.swift](../Sources/Boxmail/Support/DesignSystem.swift) |
| 动效、减少动态效果、通用焦点 | [UIMotion.swift](../Sources/Boxmail/Support/UIMotion.swift) |
| 主窗口、分栏、面板尺寸与搜索上下文 | [BoxmailApp.swift](../Sources/Boxmail/App/BoxmailApp.swift)、[ContentView.swift](../Sources/Boxmail/Views/ContentView.swift) |
| 设置布局、表单、底栏和折叠分组 | [SettingsView.swift](../Sources/Boxmail/Views/SettingsView.swift)、[SettingsFormControls.swift](../Sources/Boxmail/Views/SettingsFormControls.swift)、[SettingsActionBar.swift](../Sources/Boxmail/Views/SettingsActionBar.swift)、[SettingsDisclosureStyle.swift](../Sources/Boxmail/Views/SettingsDisclosureStyle.swift) |
| 原生菜单、流程操作与输入框 | [SelectionControlButton.swift](../Sources/Boxmail/Views/SelectionControlButton.swift)、[SettingsSelectionMenu.swift](../Sources/Boxmail/Views/SettingsSelectionMenu.swift)、[WorkflowControls.swift](../Sources/Boxmail/Views/WorkflowControls.swift) |
| 邮件、写信与 AI 布局 | [MailListView.swift](../Sources/Boxmail/Views/MailListView.swift)、[MailDetailView.swift](../Sources/Boxmail/Views/MailDetailView.swift)、[ComposerView.swift](../Sources/Boxmail/Views/ComposerView.swift)、[SummaryContentLayout.swift](../Sources/Boxmail/Support/SummaryContentLayout.swift) |

操作语义见[使用指南](USER_GUIDE.md)，数据、状态协调与原生验收方式见[开发说明](DEVELOPMENT.md)。`Design/Exports/` 是早期 HTML/CSS 设计参考；历史截图辅助理解层级，不能覆盖当前源码中的尺寸、文案和行为。

## Colors

使用低饱和度蓝色表达操作与选中状态，以接近白色的背景区分窗口、导航和内容。以下均为 `Palette` 中的 sRGB 颜色。

| 源码名称 | 值 | 用途 |
| --- | --- | --- |
| `blue` | `#3567AF` | 主操作、链接、选中标签、焦点、未读标记 |
| `blueSoft` | `#EBF1FA` | 选中行、选中筛选、写邮件入口、AI 标签浅底 |
| `chrome` | `#F8F9FB` | 窗口工具区域、设置顶部及底栏 |
| `sidebar` | `#F3F5F8` | 侧栏、分段选择底槽、普通标签 |
| `canvas` | `#F7F8FA` | 工作区底色、表单输入、次级内容容器 |
| `paper` | `#FFFFFF` | 阅读区、列表、卡片和选中分段 |
| `border` | `#D8DFE8` | 取消按钮边框、菜单悬停边框 |
| `softBorder` | `#E9EDF2` | 分隔线、静止状态的轻边框 |
| `ink` | `#232D3D` | 正文、标题和常规操作 |
| `muted` | `#606E82` | 辅助说明、日期、元数据和次级图标 |
| `success` | `#28745B` | 已保存、导出完成等成功状态 |
| `amber` | `#98651F` | 失败、待确认、凭证问题及星标 |

`accent` 是 `blue` 的别名，`accentSoft` 是 `blueSoft` 的别名。AI 入口沿用这组颜色。破坏性确认采用原生按钮的 `.destructive` 角色，不额外定义全局错误红色。

状态同时提供文字或图标：例如未读圆点配合字重、选中底色配合选中语义、失败颜色配合原因及重试。浅边框用于分隔，不独自承担可操作性或状态说明。

## Typography

### 系统字体与层级

SwiftUI 使用 `Font.system`，AppKit 使用 `NSFont.systemFont`，中文由系统字体回退处理。优先复用 `UIType`；确有局部角色差异时再使用组件已有字号与字重。

| Token | 字号 | 字重 | 用途 |
| --- | --- | --- | --- |
| `UIType.title` | 24 pt | semibold | 工作区与设置内容页标题 |
| `UIType.heading` | 17 pt | semibold | 面板标题、空态标题 |
| `UIType.section` | 14 pt | semibold | 卡片标题、列表区域标题 |
| `UIType.body` | 13 pt | regular | 通用正文、说明 |
| `UIType.caption` | 12 pt | regular | 表单、辅助说明、列表预览 |
| `UIType.small` | 11 pt | regular | 时间、计数、标签及状态 |

邮件主题在阅读区使用 20 pt semibold；列表主题使用 13 pt，未读为 semibold、已读为 medium。发件人使用 12 pt，未读为 semibold、已读为 regular。发件人聚合计数使用 11 pt medium。上述为邮件组件的局部层级，不增加新的全局字号档位。

### 排版与长内容

- 日期、数量和数值参数使用 `monospacedDigit()`，避免变化时跳动。
- 列表主题、发件人和预览保持单行；文件名和邮箱等长标识按组件使用中间省略，并通过悬停或详情提供完整值。
- 阅读区主题、错误说明、待办和期限允许自然换行；需要完整阅读的内容不套用列表的截断方式。
- 行距按内容设置：常规说明约 3 至 5 pt，纯文本邮件正文为 7 pt；不把某个页面的行距设为全局固定值。
- 邮件正文字号默认 14，可在设置中调整为 12 至 24。纯文本使用对应原生字号；HTML 默认正文样式使用同数值的 CSS px、系统字体栈和 `line-height: 1.6`，保留原邮件排版。实现见 [HTMLMailBodyView.swift](../Sources/Boxmail/Views/HTMLMailBodyView.swift) 与 [MailHTMLDocument.swift](../Sources/BoxmailCore/MailHTMLDocument.swift)。

## Layout

### 主窗口与阅读区

| 项目 | 现行值或行为 |
| --- | --- |
| 默认窗口 | 1440 × 900 pt |
| 最小窗口 | 720 × 600 pt |
| 窗口外观 | 隐藏标题栏，侧栏为系统窗口按钮保留顶部空间 |
| 主侧栏 | `UILayout.sidebar = 216`；主内容宽度达到 1080 pt 时显示 |
| 窄窗口导航 | 宽度不足 1080 pt 时从顶部按钮打开侧栏浮层 |
| 邮件列表 | 可拖动，最小 294、理想 380、最大 560 pt |
| 阅读分栏 | 最小 400 pt；阅读内容上限 `UILayout.reading = 860` |
| 文档内容 | `UILayout.document = 920`，用于文档类页面 |
| 工作区内边距 | `UILayout.pageInset = 28`；邮件阅读内容横向 24、纵向 20 pt |
| 阅读区工具栏 | 邮件操作栏高 44 pt，其下 AI 操作栏高 36 pt |

侧栏依次放置品牌、写邮件、账户、邮箱导航、智能工具和底部本机状态。邮件操作栏与 AI 操作栏保持分层；附件理解放在附件区。

### 设置与写信面板

`ContentView` 中的 `W`、`H` 为主内容可用宽高，面板尺寸按以下规则计算；这两个面板使用各自的可用宽度决定内部导航。

| 面板 | 宽度 | 高度 | 内部适配 |
| --- | --- | --- | --- |
| 设置 | `min(1000, max(700, W - 24))` | `min(750, max(500, H - 40))` | 达到 900 pt 显示 190 pt 左导航；不足时使用顶部分类标签 |
| 写信 | `min(1080, max(680, W - 24))` | `min(720, max(500, H - 40))` | AI 展开且宽度达到 940 pt 时显示 300 pt 辅栏；不足时使用 320 pt 浮层 |

设置内容宽度上限为 720 pt，内容内边距为 24 pt，顶部栏高 54 pt，底栏高 64 pt。写信中的收件人建议以独立浮层显示，不能推移字段和正文。

阅读区摘要的 `SummaryContentLayout` 按自身可用宽度排布，栏间距为 24 pt：不足 720 pt 时纵向排列；达到 720 pt 时使用两列；达到 1120 pt 且有关键信息时使用三列。这里的宽度指组件宽度，不是主窗口宽度。

### 间距与表单对齐

现有间距按角色复用，不建立源码中不存在的统一倍数网格。

| 角色 | 值 | 对应实现 |
| --- | --- | --- |
| 工作区内边距 | 28 pt | `workspacePage()` |
| 设置内容内边距 | 24 pt | `SettingsView` |
| 卡片内边距 / 内容间距 | 20 / 16 pt | `SectionCard` 默认值 |
| 表单标签列 / 列间距 | 88 / 12 pt | `SettingsFormLayout` |
| 常规字段 / 行内操作列 | 280 / 112 pt | `SettingsFormLayout` |
| 短菜单 / 端口框 | 132 / 72 pt | `SettingsFormLayout` |
| 单行控件高度 | 34 pt | 输入框、下拉框与设置底栏按钮 |
| 普通筛选间距 / 高度 | 6 / 32 pt | `FilterBar` |
| 紧凑筛选间距 / 高度 | 4 / 28 pt | `FilterBar(compact: true)` |

表单标签、字段、邻接操作按同一列对齐。超时、端口和数值参数保留短字段；签名和提示词使用多行编辑区。较窄的布局优先调整导航与辅助面板，不压缩文字到不可读字号。

## Elevation & Depth

界面主要通过背景层次、留白和 1 pt 分隔线表达结构。普通 `SectionCard` 使用白底，不添加默认阴影。工具区域、侧栏、工作区和内容纸面分别使用相应背景色。

分段选择的白色选中面板使用轻阴影：黑色不透明度 0.07、半径 2 pt、偏移 `(0, 1)`。原生菜单、浮层、Sheet 和警告框沿用系统的浮层关系，不把它们的阴影复制到普通内容卡片。

悬停和按下以局部底色变化为主，具体透明度复用按钮样式。聚焦使用下划线、边框或外轮廓，不依赖阴影表示焦点。

## Shapes

| 角色 | 圆角 | 规则 |
| --- | --- | --- |
| 通用卡片 | 12 pt | `UILayout.radius` |
| 输入、下拉、底栏按钮、紧凑筛选 | 10 pt | `UILayout.controlRadius` |
| 导航选中、写邮件、普通筛选 | 12 pt | `UILayout.selectionRadius` |
| 默认图标按钮 | 7 pt | `IconButton` 与 `ControlFeedback` 默认值 |
| 流程文字操作 | 6 pt | `WorkflowAction` |
| 搜索框 | 8 pt | `SearchField` |
| 小标签 | 4 pt | `Tag` |

主要容器、控件和选中底使用连续圆角。原生列表行保持完整矩形选中底，左侧以 1 pt 蓝线补充选中反馈；不要将列表行改成悬浮卡片。头像为浅蓝底圆角方形，圆角为尺寸的 0.3 倍，显示姓名首字符。

## Components

### 操作按钮与状态

| 组件 | 使用场景 | 现行外观与交互 |
| --- | --- | --- |
| `WorkflowAction` / `ActionButton` | 回复、发送、AI、重试、导出等流程操作 | 无描边文字，可配 SF Symbol；高 32 pt，12 pt medium，横向内边距 8 pt，图标槽宽 14 pt |
| `IconButton` / `IconMenu` | 工具栏与次要菜单 | 默认 32 × 32 pt、图标 14 pt；局部已有 28 pt 按钮；必须提供说明及可访问名称 |
| `SettingsActionBar` | 设置、账户、服务商、模型及导入面板的提交 | 底栏高 64 pt、横向内边距 24 pt；取消在前，主操作在后 |
| 底栏主按钮 | 保存、确认等提交动作 | 蓝底白字，最小 72 × 34 pt、横向内边距 16 pt、圆角 10 pt |
| 底栏取消按钮 | 取消编辑 | 白底深色文字、1 pt `border` 边框，与主按钮对齐 |

`ActionButton.kind` 的 `.primary`、`.ai`、`.softAI` 当前都映射为蓝色文字的 `WorkflowAction`；只有设置底栏的提交按钮使用上述实心蓝底。新增调用不能仅凭枚举名推断外观。

所有按钮保留以下状态，优先复用现有样式，不在页面内重写一套：

- 默认、悬停、按下：`ControlFeedback` 通过局部覆盖色反馈；普通非填充按钮悬停不透明度为 0.045、按下为 0.08。底栏按钮使用自己的主次按钮反馈。
- 选中：筛选和导航使用浅蓝底、蓝色文字与选中语义；不能只用悬停色表示持久选择。
- 聚焦：文字操作显示下划线，图标和筛选显示底部细线；输入框显示蓝色边框，底栏按钮显示外轮廓。
- 禁用：`ControlFeedback` 整体不透明度为 0.45，底栏按钮为 0.4，并通过原生禁用状态阻止操作。
- 处理中：显示进度或“正在保存…”等文字，并禁用冲突操作；异步任务结束后恢复可用状态。

### 输入、选择与折叠

- 单行设置输入复用 `.settingsTextInput()`：高 34 pt、圆角 10 pt、横向内边距 10 pt、`canvas` 底；1 pt 边框从 `softBorder` 切换为聚焦时的蓝色。
- 下拉选择复用 `WorkflowSelection`、`SettingsSelectionMenu` 与 `SelectionControlButton`。菜单跟踪、键盘及无障碍由原生 `NSPopUpButton` 保持；焦点边框为 1.5 pt，静止边框为 1 pt。
- 长选项保持字段列宽稳定，通过省略、菜单和悬停查看完整值；占位文字不能替代字段的可访问标签。
- 设置折叠使用 `SettingsDisclosureStyle`：整行可点击，最小高 36 pt；箭头与文字共同表达状态，并提供“已展开／已收起”的无障碍值。
- 多行正文、签名和提示词复用现有编辑器，保留中文输入法组合、选区、撤销和绑定更新；不在输入期间重建编辑器或抢走焦点。

### 导航、筛选与邮件列表

侧栏当前页、筛选项和设置分类均提供选中反馈。`FilterBar` 用于一组选项，`FilterButton` 用于独立筛选；`SegmentedSelection` 使用浅底槽和白色选中面板。邮件列表四项筛选在最小 294 pt 分栏内保持完整显示。

列表使用原生 `List(selection:)`。上下键切换邮件，左右键展开或折叠发件人；Shift 连续选择、Command 点击离散多选、Command-A 仅全选已加载邮件。多选时在原位置将筛选替换为批量操作栏，阅读区说明已选数量。

邮件行依次呈现发件人及日期、主题、单行预览与元数据；未读圆点、附件、星标和 AI 状态使用已有槽位。发件人聚合默认开启，展开按钮与邮件选择分开；组内邮件省略重复发件人并保留 40 pt 左缩进。加载更多、加载中和失败重试留在对应列表或分组下方。

列表可访问名称包含发件人、主题、已读状态、日期、附件、星标、总结与分类；选中状态由原生列表宣布。程序跳转只在目标需要显示时滚动，普通刷新不抢回用户位置。

### 内容卡片、标签与 AI 结果

`SectionCard` 用于设置与工作区内容分组。`Tag` 使用 11 pt medium、横向 7 pt / 纵向 3 pt 内边距；普通标签为灰色浅底，AI 标签为蓝色浅底。头像属于辅助视觉，不重复朗读姓名。

阅读区 AI 总结、翻译、AI 回复、会话 AI 分别提供入口，附件理解在正文附件区出现。流式内容使用 `AIStreamingView` 和共用 Markdown 展示，显示当前阶段与已有内容；分类确认、采用草稿等依赖完整结果的动作等待生成完成。

写信正文增加 36 pt 格式栏，复用 32 pt 图标按钮提供粗体、项目符号、编号和链接；当前格式使用浅蓝底、蓝色图标及选中语义。链接输入使用 320 pt 浮层。正文以原生 TextKit 编辑，保留选区、撤销与中文输入法，视觉签名留白不进入保存内容。

草稿同步状态以“本机草稿／等待同步服务器／已同步服务器／需要处理同步冲突”显示。冲突说明自然换行，本机副本提供“同步为新草稿”；旧编辑保存失败时提供“另存为新草稿”。会话总结按进展、未决事项、下一步排布，每项依据复用带信封图标的文字按钮；过期结果使用琥珀色说明，并禁用采用旧回复。

完成结果使用 `AIResultDisclosure`，标题整行可展开，最小高 44 pt，复制按钮独立。摘要中的待办和期限自然换行，关键信息默认展开。摘要集合先显示概要和最多两项未完成待办，再按项展开完整详情；移除总结收录项与删除邮件使用不同动作和说明。

### 搜索、空态与错误反馈

- 顶部搜索以“邮件搜索”标明范围，保留清除按钮和返回入口；搜索期间侧栏不继续高亮原页面。离开搜索后保留附件页等辅助工作区的局部筛选及滚动状态。
- `SearchField` 高 34 pt、白底、圆角 8 pt，聚焦时底部蓝色细线；日期面板宽 360 pt，年月菜单保留独立槽位与原生操作。
- `EmptyState` 以图标、标题、说明和可选动作组成，内边距 28 pt、说明宽度上限 340 pt。首次无数据、筛选无结果、未选择邮件分别给出对应说明；筛选无结果时提供清除条件的路径。
- 局部失败在对应区域说明原因并提供重试；`WorkflowNotice` 使用可换行、可选择的文字。保存失败保留输入；保存成功但刷新失败必须区分两种结果。
- 发送前确认收件人、主题和附件；永久清空与移除账户用原生破坏性确认说明作用范围。最近一次手动邮件操作提供撤销，自动已读不占用该撤销记录。

### 滚动、键盘与可访问性

普通滚动区复用 `OverlayScrollView` 与 `.borderlessScrollers()`，使用无描边细滑块。收件人与抄送长名单是显式例外：内容溢出时保留可见的原生滚动条；全局外观刷新不能抹掉该例外。

图标按钮有 `.help` 和可访问名称，装饰图标隐藏；折叠和选择提供状态语义。焦点提示不遮挡内容，键盘操作复用原生菜单、列表和编辑器。列表快捷键经 `FocusedValue` 限定作用域，编辑文字时继续使用编辑器的选择、删除与撤销。常用快捷键以[使用指南](USER_GUIDE.md)中的清单为准。

新增或变更界面的验收要求：检查键盘可达性、焦点可见性、长文案、颜色以外的状态提示和 VoiceOver 名称、值及阅读顺序。当前使用固定字号，不据此宣称已支持所有字号缩放场景。源码存在可访问属性、历史 AX 检查通过，也不代表已完成当前版本的 VoiceOver 全流程验收。

### 动效

统一通过 `UIMotion` 读取系统“减少动态效果”，不用页面私有的任意时长替代。

| Token | 常规模式 | 减少动态效果 |
| --- | --- | --- |
| `feedback` | `easeOut`，0.14 秒 | `easeOut`，0.08 秒 |
| `selection` | `easeOut`，0.22 秒 | `easeOut`，0.08 秒 |
| `disclosure` | `smooth`，0.26 秒，`extraBounce: 0` | 无展开动画 |
| `reveal` | 透明度与纵向 -6 pt 位移组合 | 仅透明度 |

选中底板可使用 `matchedGeometryEffect`，减少动态效果时使用静态选中底；数字替换、图标替换及弹跳也跟随系统偏好。流式生成不为每个新增字符触发布局动画。按压缩放只在共用样式的填充模式下启用，减少动态效果时关闭。

## Do's and Don'ts

### 应当

- 新增界面先查找现有组件，优先复用 `Palette`、`UIType`、`UILayout`、`SettingsFormLayout` 和 `UIMotion`。
- 让主要内容、次级说明、操作与状态在密集界面中仍可区分；通过留白、背景和轻分隔组织结构。
- 每个异步区域明确加载、完成、失败及可恢复路径，保存失败保留用户输入。
- 变更设计值或组件行为时，同步更新本文、受影响的使用指南和开发说明，避免仅修改文档中的数字。

### 避免

- 为单页复制一套近似颜色、字号、圆角或按钮状态，或把局部视觉值提升为全局规则。
- 给普通列表行与内容卡片添加装饰性大阴影，或为 AI 功能建立另一套配色。
- 以更小字号、截断错误原因或隐藏关键入口来适配窄窗口。
- 通过无语义点击区域替代原生按钮、菜单或列表，覆盖编辑器快捷键，或只用颜色说明状态。
- 把历史截图中的旧入口、固定面板尺寸或验证结论视为当前实现依据。

### 变更验收清单

以下用于后续 UI 变更验收，本次文档整理不构成新一轮运行验收。

- [ ] 主窗口核对 1440 × 900 pt 与 720 × 600 pt，并检查 1080 pt 侧栏切换前后。
- [ ] 邮件列表核对 294、380、560 pt，包含四项筛选、长主题、聚合展开、多选和加载失败。
- [ ] 设置核对 900 pt、写信核对 940 pt 切换前后；底栏、字段、已有抄送和密送保持可见。
- [ ] 核对默认、悬停、按下、聚焦、选中、禁用、处理中、空态和错误状态。
- [ ] 用键盘完成相关流程，检查中文输入法、长收件人、长文件名、长错误文字和 VoiceOver 语义。
- [ ] 开启系统“减少动态效果”，确认位移、展开、底板移动和符号动效按规范降级。
- [ ] 使用开发说明中的隔离验收方式记录受影响场景及验证边界；只对受影响行为运行相应回归。
