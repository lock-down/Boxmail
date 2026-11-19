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
  navigation: "12pt"
  icon: "8pt"
  segment: "14pt"
spacing:
  page-inset: "28pt"
  settings-inset: "24pt"
  section-inset: "20pt"
  section-content-gap: "16pt"
  form-column-gap: "12pt"
  filter-gap: "4pt"
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
    height: "36pt"
    padding: "0 10pt"
  filter-bar-selected:
    backgroundColor: "{colors.blue-soft}"
    textColor: "{colors.blue}"
    rounded: "{rounded.control}"
    height: "32pt"
    padding: "0 12pt"
  section-card:
    backgroundColor: "{colors.paper}"
    rounded: "{rounded.surface}"
    padding: "20pt"
---

# Boxmail UI 规范

## Overview

### 定位与适用范围

Boxmail 是原生 macOS AI 邮件客户端。界面围绕查找、阅读、撰写和处理邮件组织，采用紧凑列表、清楚的内容层级、系统字体和蓝灰配色。AI 能力放在邮件及附件的操作上下文中。

本规范于 2026-11-09 从现有 SwiftUI / AppKit 实现及开发说明整理，2026-11-18 对照当前源码更新，用于新增界面、维护共用组件和界面验收。风格描述是对现有实现的归纳。当前主窗口与系统设置场景固定使用浅色外观；深色主题尚未建立对应的颜色与组件规范。

本文记录 Boxmail 0.1.10 的现行界面。后续方案单列，已完成的功能和验收记录见 [变更记录](../CHANGELOG.md#0110--2026-11-19)。

2026-11-16 的实机观察见 [Filo 对标调研](research/FILO_BENCHMARK_2026-11-16.md)。下文按当前界面描述控件和布局，后续候选见对应章节。

本文数值均为原生界面的逻辑点（pt），不按截图像素换算。邮件 HTML 正文使用 WebKit 的 CSS 单位，单独遵循正文规则。顶部 YAML 提供可读取的现有设计值；`system` 表示系统字体，不指定字体文件。运行时仍由下表中的 Swift 常量和组件实现提供样式；修改共用设计值时应同步更新源码与本文。

### 依据与维护入口

| 范围 | 实现依据 |
| --- | --- |
| 颜色、字体、基础尺寸、标签、卡片、空态 | [DesignSystem.swift](../Sources/Boxmail/Support/DesignSystem.swift) |
| 动效与减少动态效果 | [UIMotion.swift](../Sources/Boxmail/Support/UIMotion.swift) |
| 表格列宽、排序控件和弹窗尺寸 | [AttachmentListLayout.swift](../Sources/Boxmail/Support/AttachmentListLayout.swift)、[TableSortButton.swift](../Sources/Boxmail/Views/TableSortButton.swift)、[WorkspaceSheetLayout.swift](../Sources/Boxmail/Support/WorkspaceSheetLayout.swift) |
| 按钮尺寸、外观、反馈与焦点 | [ControlStyle.swift](../Sources/Boxmail/Support/ControlStyle.swift)、[ActionButton.swift](../Sources/Boxmail/Views/ActionButton.swift)、[IconButton.swift](../Sources/Boxmail/Views/IconButton.swift)、[SelectionButton.swift](../Sources/Boxmail/Views/SelectionButton.swift) |
| 主窗口、缩放、分栏、面板尺寸与搜索上下文 | [BoxmailApp.swift](../Sources/Boxmail/App/BoxmailApp.swift)、[ContentView.swift](../Sources/Boxmail/Views/ContentView.swift)、[WindowTitlebarRegion.swift](../Sources/Boxmail/Support/WindowTitlebarRegion.swift)、[MainWindowLayout.swift](../Sources/Boxmail/Support/MainWindowLayout.swift) |
| 设置布局、表单、底栏和折叠分组 | [SettingsView.swift](../Sources/Boxmail/Views/SettingsView.swift)、[SettingsFormControls.swift](../Sources/Boxmail/Views/SettingsFormControls.swift)、[SettingsActionBar.swift](../Sources/Boxmail/Views/SettingsActionBar.swift)、[SettingsDisclosureStyle.swift](../Sources/Boxmail/Views/SettingsDisclosureStyle.swift) |
| 会话依据、收件人展开与摘要标题 | [MailSourceButton.swift](../Sources/Boxmail/Views/MailSourceButton.swift)、[RecipientDetailsView.swift](../Sources/Boxmail/Views/RecipientDetailsView.swift)、[SummaryCard.swift](../Sources/Boxmail/Views/SummaryCard.swift) |
| 收件信息与滚动命中 | [RecipientAddressList.swift](../Sources/Boxmail/Views/RecipientAddressList.swift)、[MailRecipientOverlay.swift](../Sources/Boxmail/Views/MailRecipientOverlay.swift)、[ScrollEventRouting.swift](../Sources/Boxmail/Support/ScrollEventRouting.swift) |
| 原生菜单、流程操作与输入框 | [SelectionControlButton.swift](../Sources/Boxmail/Views/SelectionControlButton.swift)、[SettingsSelectionMenu.swift](../Sources/Boxmail/Views/SettingsSelectionMenu.swift)、[WorkflowControls.swift](../Sources/Boxmail/Views/WorkflowControls.swift) |
| 邮件、写信与 AI 布局 | [MailListView.swift](../Sources/Boxmail/Views/MailListView.swift)、[MailDetailView.swift](../Sources/Boxmail/Views/MailDetailView.swift)、[ComposerView.swift](../Sources/Boxmail/Views/ComposerView.swift)、[SummaryContentLayout.swift](../Sources/Boxmail/Support/SummaryContentLayout.swift) |
| 共用列表、附件分页与 ZIP 预览 | [AttachmentsView.swift](../Sources/Boxmail/Views/AttachmentsView.swift)、[AttachmentListView.swift](../Sources/Boxmail/Views/AttachmentListView.swift)、[WorkspaceList.swift](../Sources/Boxmail/Views/WorkspaceList.swift)、[SummaryOverviewView.swift](../Sources/Boxmail/Views/SummaryOverviewView.swift)、[OrganizationReviewList.swift](../Sources/Boxmail/Views/OrganizationReviewList.swift)、[ListPagination.swift](../Sources/Boxmail/Views/ListPagination.swift)、[ArchiveAttachmentView.swift](../Sources/Boxmail/Views/ArchiveAttachmentView.swift) |
| 正文格式栏、颜色与签名留白 | [RichTextFormatBar.swift](../Sources/Boxmail/Views/RichTextFormatBar.swift)、[RichTextColorMenu.swift](../Sources/Boxmail/Views/RichTextColorMenu.swift)、[PlainTextEditor.swift](../Sources/Boxmail/Views/PlainTextEditor.swift) |
| 共用日期、AI 阅读与助手输入 | [CalendarMonthView.swift](../Sources/Boxmail/Views/CalendarMonthView.swift)、[DateTimeSelection.swift](../Sources/Boxmail/Views/DateTimeSelection.swift)、[AnalysisDocumentView.swift](../Sources/Boxmail/Views/AnalysisDocumentView.swift)、[AnalysisTableView.swift](../Sources/Boxmail/Views/AnalysisTableView.swift)、[AnalysisCodeBlockView.swift](../Sources/Boxmail/Views/AnalysisCodeBlockView.swift)、[AssistantComposerView.swift](../Sources/Boxmail/Views/AssistantComposerView.swift)、[TextSubmitShortcut.swift](../Sources/Boxmail/Support/TextSubmitShortcut.swift) |
| R1-R5 工作区与表单 | [WorkspaceHeader.swift](../Sources/Boxmail/Views/WorkspaceHeader.swift)、[MailQueryEditor.swift](../Sources/Boxmail/Views/MailQueryEditor.swift)、[RuleEditor.swift](../Sources/Boxmail/Views/RuleEditor.swift)、[FollowUpEditor.swift](../Sources/Boxmail/Views/FollowUpEditor.swift)、[SendScheduleForm.swift](../Sources/Boxmail/Views/SendScheduleForm.swift)、[AssistantWorkspaceView.swift](../Sources/Boxmail/Views/AssistantWorkspaceView.swift) |

操作语义见[使用指南](USER_GUIDE.md)，数据、状态协调与原生验收方式见[开发说明](DEVELOPMENT.md)。历史截图仅辅助理解层级，当前尺寸、文案和行为以本文及关联源码为准。

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

`accent` 是 `blue` 的别名，`accentSoft` 是 `blueSoft` 的别名。AI 入口沿用这组颜色。

分类标签使用成对的前景色和浅底色。邮件列表、阅读区、智能整理和分类管理沿用同一套配色。工作项目为蓝、订阅资讯为紫、账单票据为暖棕、社交通知为青、个人往来为玫瑰色。未分类使用中性色，自定义分类按已有分类 ID 从同一组颜色取值。标签始终显示分类名称。详见 [CategoryTone](../Sources/Boxmail/Support/CategoryTone.swift)。

破坏性确认采用原生按钮的 `.destructive` 角色，不额外定义全局错误红色。

状态同时提供文字或图标：例如未读圆点配合字重、选中底色配合选中语义、失败颜色配合原因及重试。浅边框用于分隔，不独自承担可操作性或状态说明。

## Typography

### 系统字体与层级

SwiftUI 使用 `Font.system`，AppKit 使用 `NSFont.systemFont`，中文由系统字体回退处理。优先复用 `UIType`；确有局部角色差异时再使用组件已有字号与字重。

| Token | 字号 | 字重 | 用途 |
| --- | --- | --- | --- |
| `UIType.title` | 24 pt | semibold | 通用工作区与设置内容页标题；新增工作区的 `WorkspaceHeader` 使用局部 22 pt 层级 |
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
| 窗口外观 | 隐藏标题栏，侧栏为系统窗口按钮保留顶部空间；双击顶部空白区域以 AppKit 原生动画填满当前屏幕可用区域，再次双击恢复此前位置与大小；初始已最大化时还原到居中的默认尺寸，小屏按可用区域适配，保留拖动 |
| 主侧栏 | `UILayout.sidebar = 216`；主内容宽度达到 1080 pt 时显示 |
| 窄窗口导航 | 宽度不足 1080 pt 时从顶部按钮打开侧栏浮层 |
| 邮件列表 | 可拖动，最小 294、理想 380、最大 560 pt |
| 阅读分栏 | 最小 400 pt；阅读内容上限 `UILayout.reading = 860` |
| 邮件助手 | 宽 360 pt。中间区域能同时容纳邮件列表、阅读区和助手时并排，否则在阅读区右侧覆盖显示。 |
| 文档内容 | `UILayout.document = 920`，用于文档类页面 |
| 工作区内边距 | `UILayout.pageInset = 28`；邮件阅读内容横向 24、纵向 20 pt |
| 阅读区工具栏 | 邮件操作栏高 44 pt，其下 AI 操作栏高 36 pt |

侧栏依次放置品牌、写邮件、账户、邮箱导航、智能工具和底部本机状态。邮件工作台在同一页切换跟进和摘要，右侧助手由顶部工具栏或 Command-Shift-J 展开和收起。邮件操作栏与 AI 操作栏保持分层。发件人姓名、邮箱和时间同排，长邮箱保留完整悬停提示。“转发”在回复下拉箭头之后，与“回复”使用相同的文字按钮、蓝色和尺寸；下拉菜单仅保留“全部回复”。整封理解集中在 AI 操作栏，附件区保留文件预览与独立附件分析，避免重复同一入口。

### 弹窗与写信面板

`WorkspaceSheetLayout` 统一计算主要面板尺寸，`W`、`H` 为呈现该面板的可用宽高。主窗口通过环境传递可用尺寸；嵌套弹窗继承当前面板的实际尺寸，内容滚动，底部操作固定。

| 面板 | 宽度 | 高度 | 内部适配 |
| --- | --- | --- | --- |
| 设置 | `min(1000, max(700, W - 24))` | `min(750, max(500, H - 40))` | 达到 900 pt 显示 190 pt 左导航；不足时使用顶部分类标签 |
| 写信 | `min(1080, max(680, W - 24))` | `min(720, max(500, H - 40))` | AI 展开且宽度达到 940 pt 时显示 300 pt 辅栏；不足时使用 320 pt 浮层 |
| 附件预览 | `min(1080, max(640, W - 24))` | `min(720, max(480, H - 40))` | 顶部文件操作与预览导航固定，原件及结果在内容区滚动 |
| 分类管理 | `min(760, max(640, W - 24))` | `min(520, max(480, H - 40))` | 分类列表与编辑区各自保留可用空间 |
| 自定义模型 API | `min(680, max(640, W - 24))` | `min(720, max(480, H - 40))` | 表单按可用高度滚动，取消与添加固定在底部 |

设置内容宽度上限为 720 pt，内容内边距为 24 pt，顶部栏高 54 pt，底栏高 64 pt。写信中的收件人建议以独立浮层显示，不能推移字段和正文。

阅读区和工作台详情的 `SummaryContentLayout` 在至少 720 pt 的组件宽度下并排展示概要与关键事实、待办与下一步，栏间距 24 pt。窄卡片顺序堆叠，没有待办或建议时左栏占全宽。

### 间距与表单对齐

控件尺寸与间距按角色复用，按钮及选择组件使用 4 pt 步长；原有正文与列表排版保持各自的阅读密度。

| 角色 | 值 | 对应实现 |
| --- | --- | --- |
| 工作区内边距 | 28 pt | `workspacePage()` |
| 设置内容内边距 | 24 pt | `SettingsView` |
| 卡片内边距 / 内容间距 | 20 / 16 pt | `SectionCard` 默认值 |
| 表单标签列 / 列间距 | 88 / 12 pt | `SettingsFormLayout` |
| 常规字段 / 行内操作列 | 280 / 112 pt | `SettingsFormLayout` |
| 短菜单 / 端口框 | 132 / 72 pt | `SettingsFormLayout` |
| 紧凑 / 常规 / 表单控件高度 | 28 / 32 / 36 pt | `UIControlSize`；表单输入、下拉和底栏按钮共用 36 pt |
| 普通筛选间距 / 高度 | 4 / 32 pt | `FilterBar` |
| 紧凑筛选间距 / 高度 | 4 / 28 pt | `FilterBar(compact: true)` |

表单标签、字段、邻接操作按同一列对齐。通知偏好、系统通知状态与设置入口共用一行，宽度不足时换行。整理规则的名称与处理意图并排，搜索范围字段在空间充足时同排，AI 处理、邮件动作与运行方式分别横排其选项。超时、端口和数值参数保留短字段；签名和提示词使用多行编辑区。较窄的布局优先调整导航与辅助面板，不压缩文字到不可读字号。

## Elevation & Depth

界面主要通过背景层次、留白和 1 pt 分隔线表达结构。普通 `SectionCard` 使用白底，不添加默认阴影。工具区域、侧栏、工作区和内容纸面分别使用相应背景色。

分段选择的白色选中面板使用轻阴影：黑色不透明度 0.07、半径 2 pt、偏移 `(0, 1)`。原生菜单、浮层、Sheet 和警告框沿用系统的浮层关系，不把它们的阴影复制到普通内容卡片。

悬停和按下以局部底色变化为主，具体透明度复用按钮样式。SwiftUI 按钮聚焦时显示蓝色外轮廓，原生输入及菜单使用边框，不依赖阴影表示焦点。

## Shapes

| 角色 | 圆角 | 规则 |
| --- | --- | --- |
| 通用卡片 | 12 pt | `UILayout.radius` |
| 文字动作、主次按钮、筛选、日期、回复预设、输入及下拉 | 10 pt | `UILayout.controlRadius`；背景、点击区域与反馈层采用同一圆角 |
| 导航选中 | 12 pt | `UILayout.navigationRadius` |
| 图标按钮与格式菜单 | 8 pt | `UILayout.iconRadius` |
| 分段选择外槽 | 14 pt | `UILayout.segmentRadius`，与 4 pt 内边距、10 pt 内层圆角配合 |
| 搜索框 | 8 pt | `SearchField` |
| 小标签 | 4 pt | `Tag` |

主要容器、控件和选中底使用连续圆角。原生邮件列表行保持完整矩形选中底，左侧以 1 pt 蓝线补充选中反馈；附件表格复用相同的 `blueSoft` 浅蓝底，不添加左侧标线。不要将列表行改成悬浮卡片。头像为浅蓝底圆角方形，圆角为尺寸的 0.3 倍，显示姓名首字符。

## Components

### 操作按钮与状态

| 组件 | 使用场景 | 现行外观与交互 |
| --- | --- | --- |
| `ActionButton` | 回复、发送、AI、重试、导出及底栏提交 | 常规高 32 pt、12 pt medium、横向内边距 12 pt；图标为 14 pt regular，槽宽 16 pt，与文字间距 8 pt |
| `SettingsInlineAction` | 表单操作列 | 仅包装 `ActionButton` 的表单尺寸、112 pt 列宽与左对齐 |
| `SelectionButton` | 独立筛选、AI 工具栏、回复预设及分段选择项 | 共用尺寸、10 pt 圆角、选中语义、焦点和反馈；分组可传入同一高亮命名空间 |
| `IconButton` / `IconMenu` | 工具栏与次要菜单 | 默认 32 × 32 pt、图标 14 pt；局部已有 28 pt 按钮；必须提供说明及可访问名称 |
| `SettingsActionBar` | 设置、账户、服务商、模型及导入面板的提交 | 底栏高 64 pt、横向内边距 24 pt；取消在前，主操作在后 |
| 底栏主按钮 | 保存、确认等提交动作 | 蓝底白字，最小 72 × 36 pt、横向内边距 16 pt、圆角 10 pt |
| 底栏取消按钮 | 取消编辑 | 白底深色文字、1 pt `border` 边框，与主按钮对齐 |

文字动作、选择项、排序和来源等控件复用 `controlLabel()` 的标签边界：紧凑、常规和表单尺寸默认保留对称的 8、12、12 pt 横向内边距，内容在控件内垂直居中，背景、指针反馈与焦点使用同一边界。长待办和下一步操作可自然增高；不要只设置单侧内边距，也不要让文字或箭头贴住反馈层边缘。原生下拉的文字绘制复用 `drawSelectionText()`，按实际字体高度居中。

`ActionButton` 用 `color` 表达文字颜色，用 `emphasis` 明确外观：`.plain` 为文字动作，`.tinted` 为浅蓝底入口，`.secondary` 为白底描边，`.primary` 为蓝底白字。AI 与普通动作按同一规则配置；`SettingsActionBar` 直接使用该组件，不再维护独立按钮样式。

所有按钮保留以下状态，优先复用现有样式，不在页面内重写一套：

- 默认、悬停、按下：`ControlFeedback` 通过局部覆盖色反馈；普通非填充按钮悬停不透明度为 0.045、按下为 0.08。主按钮悬停为 0.08、按下为 0.16；SwiftUI 与 AppKit 共用 `ControlStateAppearance` 中的反馈参数。
- 选中：筛选和导航使用浅蓝底、蓝色文字与选中语义；不能只用悬停色表示持久选择。
- 聚焦：SwiftUI 按钮统一使用 `controlFocus()` 的 2 pt 蓝色外轮廓；原生字段保留 1.5 pt 焦点边框，原生格式菜单使用 2 pt 内轮廓，避免绘制被控件边界裁切。
- 禁用：SwiftUI 按钮整体不透明度统一为 0.45，禁用时不显示悬停与焦点反馈，并通过原生禁用状态阻止操作。
- 处理中：显示进度或“正在保存…”等文字，并禁用冲突操作；异步任务结束后恢复可用状态。

### 输入、选择与折叠

- 单行设置输入复用 `.settingsTextInput()`：高 36 pt、圆角 10 pt、横向内边距 10 pt、`canvas` 底；1 pt 边框从 `softBorder` 切换为聚焦时的蓝色。
- 下拉选择复用 `WorkflowSelection`、`SettingsSelectionMenu` 与 `SelectionControlButton`。菜单跟踪、键盘及无障碍由原生 `NSPopUpButton` 保持；焦点边框为 1.5 pt，静止边框为 1 pt。
- 长选项保持字段列宽稳定，通过省略、菜单和悬停查看完整值；占位文字不能替代字段的可访问标签。
- 设置折叠使用 `SettingsDisclosureStyle`：整行可点击，最小高 36 pt；箭头与文字共同表达状态，并提供“已展开／已收起”的无障碍值。
- 多行正文、签名和提示词复用现有编辑器，保留中文输入法组合、选区、撤销和绑定更新；不在输入期间重建编辑器或抢走焦点。

写信与回复共用收件人输入组件：空收件人、抄送和密送之间的鼠标或 Tab 切换不展示空候选面板，输入关键词后才显示联系人建议。原生控件启用状态仅在值变化时更新，焦点交接保留输入法、选区与编辑器生命周期。

### 导航、筛选与邮件列表

侧栏当前页、筛选项和设置分类均提供选中反馈。邮箱区域依次为收件箱、邮件工作台、星标邮件、草稿箱、发送管理、已发送、已删除、已归档、垃圾邮件、附件中心。导航行高 32 pt、间距 4 pt，图标为 14 pt regular SF Symbol、槽宽 20 pt、与文字间距 8 pt；分组标题上方 16 pt、下方 4 pt。保存视图分组仅在有内容时显示，条目提供选中、焦点与完整名称提示。邮件工作台使用清单图标，智能整理使用双层收件盘，发送管理使用发件盘。

`FilterBar` 与独立筛选均复用 `SelectionButton`；`SegmentedSelection` 同样复用该组件，使用浅底槽和白色选中面板，外槽内边距与项间距均为 4 pt。邮件列表四项筛选在最小 294 pt 分栏内保持完整显示。分类菜单和保存视图书签统一使用 32 pt 控件边界。

列表使用原生 `List(selection:)`。上下键切换邮件，左右键展开或折叠发件人；Shift 连续选择、Command 点击离散多选、Command-A 仅全选已加载邮件。多选时在原位置将筛选替换为批量操作栏，阅读区说明已选数量。

邮件行依次呈现发件人及日期、主题、单行预览与元数据；未读圆点、附件、星标和 AI 状态使用已有槽位。发件人聚合默认开启，展开按钮与邮件选择分开；组内邮件省略重复发件人并保留 40 pt 左缩进。加载更多、加载中和失败重试留在对应列表或分组下方。

列表可访问名称包含发件人、主题、已读状态、日期、附件、星标、总结与分类；选中状态由原生列表宣布。程序跳转只在目标需要显示时滚动，普通刷新不抢回用户位置。

### 附件中心与资料包

附件中心位于侧栏“垃圾邮件”下方，与智能整理共用 `WorkspaceList` / `WorkspaceListRow`，使用 10 pt 圆角、轻边框、白色表面、水平分隔及 `ControlFeedback` 悬停/按下反馈，以 `LazyVStack` 显示后端分页结果，每页 50 条。底部固定 40 pt 分页栏，显示当前范围、总数、页码及前后翻页按钮；首尾页和加载期间禁用对应按钮。搜索、类型、排序或账户变化回到第一页，筛选与排序覆盖整个账户；默认按原邮件日期倒序，同日期按文件名自然排序。表头与数据使用同一套 `AttachmentListLayout` 宽度，图标独立成列，各列标题与内容统一左对齐，操作标题在整组按钮上方居中。表头使用 11 pt 常规字重且不显示竖向分隔线；`TableSortButton` 高 28 pt，宽度随文字、4 pt 间距、12 pt 箭头槽及左右各 8 pt 内边距确定，列宽由外部容器分配；悬停和焦点反馈不铺满整列。箭头槽始终保留，切换排序时不挤动标题；所有表头文字保持相同的辅助色，当前排序列通过上下箭头表达方向；排序按钮的 leading 对齐线位于内边距之后，使标题文字与数据列对齐，辅助功能值同时标明升序或降序。选中行复用收件列表的 `blueSoft` 浅蓝底，保留原文字和图标颜色，以及行按钮的选中与无障碍语义，支持上下键移动选择、回车预览。文件名使用 13 pt medium，元数据使用 11 至 12 pt，ZIP 已有结果但仍有未完成文件时显示“部分理解”，长文件名中间省略并通过悬停显示完整值。名称、大小、日期可排序，行内保留 32 pt 图标操作，双击或回车预览。

表格可用宽度达到 960 pt 时独立显示原邮件与发件人列，大小、日期、状态和操作列分别为 96、112、96、104 pt；扣除固定列、16 pt 水平内边距与 20 pt 列间距后，名称列理想宽度为余量的 48%，上限 520 pt，原邮件列承接余量。不足 960 pt 时将原邮件主题并入文件名下方，大小、日期、状态和操作列分别为 64、84、72、104 pt。不足 760 pt 时，理解状态也并入文件名下方，移除独立状态列，给长文件名保留空间。表头和数据行共用列宽与间距，最小窗口不靠横向溢出容纳固定列；搜索、类型筛选、排序和三项附件操作保留。

ZIP 预览使用“文件目录／整体整理”切换。文件目录左侧按包内路径显示文件、大小与理解状态，右侧查看单文件结果或原文件；加密、不支持、超限及嵌套压缩包说明原因。整体整理按总览、文件归类、关联差异与下一步行动呈现，来源按钮可定位到对应包内文件。未处理文件和理解覆盖数量始终可见。包内文件不增加邮件顶层附件数量。

智能整理的收件箱分类也使用相同列表容器和行反馈，每页 50 封，分类计数覆盖当前账户完整收件箱；切换分类回到第一页，各账户分别保留自己的页码和位置。页面标题、整理操作和分类筛选固定，只有列表行区域滚动；分类邮件及建议的分页栏各自固定在对应列表底部，翻页后只重置该列表的滚动位置。空分类提示位于列表内容区内，与底部分页保持在同一容器。共用列表的外层、滚动内容和行堆栈均明确靠左，视口因滚动条收缩时不把固定列宽的行居中挤偏。分类建议每页 50 条，“确认应用分类”作用于本次任务全部建议，不随当前页缩小范围。可用内容高度不足 720 pt，或任务正在运行／等待审阅时，收紧标题、操作和进度区，分类卡片改为带完整计数的原生菜单；保留列表空间及全部整理操作。

### 内容卡片、标签与 AI 结果

会话历史中的回复、原邮件跳转及归档／恢复操作按可用宽度换行。会话依据使用 `MailSourceButton`，长发件人名称中间省略，日期保持完整，悬停与可访问名称保留完整来源说明；不能用强制保持完整宽度的普通动作标签承载无界来源名称。

`SectionCard` 用于设置与工作区内容分组。`Tag` 使用 11 pt medium、横向 7 pt / 纵向 3 pt 内边距；普通标签为灰色浅底，AI 标签为蓝色浅底。头像属于辅助视觉，不重复朗读姓名。

阅读区整封理解、翻译、AI 回复、会话 AI 分别提供入口；附件区不重复放置整封理解按钮，单文件分析保留在预览与附件菜单中。整封结果和回复预览共用 `MailAIContextNotice` 显示文件覆盖范围，未完整纳入时使用提醒色，并可展开核对 ZIP 子项。流式内容使用 `AIStreamingView` 和共用 Markdown 展示，显示当前阶段与已有内容；分类确认、采用草稿等依赖完整结果的动作等待生成完成。

写信正文采用 36 pt 格式栏，顺序为粗体、文字颜色、字号、项目符号、编号与链接。原生字号菜单为 64 × 32 pt，使用 12 pt regular 辅助色文字，提供 8 至 72 pt 常用字号；文字与箭头整体居中，悬停、按下及焦点反馈与图标按钮一致。混合字号在入口显示“混合”，菜单与无障碍值保留“混合字号”。图标控件统一为 32 × 32 pt、14 pt regular SF Symbol，同组间距为 4 pt，复用 `UILayout.iconControl`、`iconSize`、`iconGap` 与 `iconRadius`，不插入额外的分隔留白。粗体与列表选中时使用浅蓝底、蓝色图标及选中语义。颜色入口使用同尺寸的字母图标配 14 × 2 pt 色条，原生菜单使用 12 pt 系统字体，以非模板色样保留每项真实 sRGB 颜色，同时提供名称与选中状态；文字橙色预设为 `#BF5700`，与状态琥珀色分开，菜单色样、入口色条及正文保持一致；支持恢复默认与自定不透明颜色，自定颜色在 260 pt 浮层中预览并明确应用。混合字号和颜色以文字提供无障碍反馈。链接输入使用 320 pt 浮层。列表编号与符号跟随该项开头文字的字号和颜色，折行缩进按标记宽度计算。正文以原生 TextKit 编辑，选区格式与后续输入格式分开处理，保留选区、撤销与中文输入法，视觉签名留白不进入保存内容。

短正文的签名可通过段落布局置于编辑区底部，长正文时跟随文末。普通单击签名前的视觉留白定位到正文末行，实际签名文字保持可编辑；拖选、Shift 选择及非空选区继续使用原生行为。调整窗口、编辑签名、撤销或重开草稿后保持相同定位规则，不以占位换行撑开正文。

草稿同步状态以“本机草稿／等待同步服务器／已同步服务器／需要处理同步冲突”显示。冲突说明自然换行，本机副本提供“同步为新草稿”；旧编辑保存失败时提供“另存为新草稿”。会话总结按进展、未决事项、下一步排布，每项依据复用带信封图标的文字按钮；过期结果使用琥珀色说明，并禁用采用旧回复。

完成结果使用 `AIResultDisclosure`，标题整行可展开，最小高 44 pt，复制按钮独立。摘要的关键事实使用四行固定标签。同组事实合并在一个内容区，保留不同期限、金额及限制，缺项显示短横线。待办文字和期限可换行，「收录跟进」作为同行独立按钮保留颜色和对齐。收件人展开、摘要待办和下一步操作也使用对称的标签边界。工作台的摘要与附件中心、智能整理共用列表滚动表面，筛选和操作固定，摘要内容单独滚动；切换“列表／已移除”或账户时回到列表开头。先显示概要和最多两项未完成待办，再按项展开完整详情；移除总结收录项与删除邮件使用不同动作和说明。

### 搜索、空态与错误反馈

- 顶部搜索以“邮件搜索”标明范围，保留清除按钮和返回入口；搜索期间侧栏不继续高亮原页面。离开搜索后保留附件页等辅助工作区的局部筛选及滚动状态。
- `SearchField` 高 34 pt、白底、圆角 8 pt，聚焦时底部蓝色细线；日期面板宽 360 pt，年月菜单保留独立槽位与原生操作。
- `EmptyState` 以图标、标题、说明和可选动作组成，内边距 28 pt、说明宽度上限 340 pt。首次无数据、筛选无结果、未选择邮件分别给出对应说明；筛选无结果时提供清除条件的路径。
- 局部失败在对应区域说明原因并提供重试；`WorkflowNotice` 使用可换行、可选择的文字。保存失败保留输入；保存成功但刷新失败必须区分两种结果。
- 发送前确认收件人、主题和附件；永久清空与移除账户用原生破坏性确认说明作用范围。最近一次手动邮件操作提供撤销，自动已读不占用该撤销记录。

### 滚动、键盘与可访问性

普通滚动区复用 `OverlayScrollView` 与 `.borderlessScrollers()`，使用无描边细滑块。收件箱等原生列表和表格遵循 macOS 的滚动条偏好，窗口外观刷新时保留系统滑块和视口宽度。收件人、抄送和密送共用 `RecipientDetailsView`：收起时显示单行摘要，展开长名单高 240 pt，短名单按内容高度显示；内容溢出时保留可见的原生滚动条，全局外观刷新不能抹掉该例外。鼠标位于名单内时，滚轮由名单消费；移到正文后立即滚动正文，无需先滚完名单，名单内到达边界后也可交还外层；保留原生文字选择与复制。邮件头、HTML 与纯文本引用、转发预览和草稿搜索详情使用相同组件，HTML 的发件人、日期、主题及其余正文保持原排版。

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

选中底板可使用 `matchedGeometryEffect`，减少动态效果时使用静态选中底；数字替换、图标替换及弹跳也跟随系统偏好。流式生成不为每个新增字符触发布局动画。按钮按下只改变覆盖色，不改变内容尺寸或位置。

## 邮件阅读与处理

保留蓝灰配色、系统字体和原生分栏。「回复」与「转发」并排。改动缘由见 [调研记录](research/FILO_BENCHMARK_2026-11-16.md#boxmail-日常版-uiue-步骤记录)。

| 单元 | 当前行为 |
| --- | --- |
| U1 预览 | HTML 邮件从清理后的 HTML 提取列表文字，排除纯文本替代部分混入的样式；无 HTML 时继续使用纯文本。仅变更预览投影，保留正文和原件 |
| U2 来源返回 | 从分类结果打开邮件后，沿用顶部来源栏提供“返回分类结果”。分类工作区按账户保留筛选、分页、实际滚动偏移与选中；侧栏重进恢复，切换分类及翻页复位滚动。状态仅在本次运行保留 |
| U3 摘要 | 概要默认显示三行，可展开全部内容；无待办时只显示简短状态，实际待办及勾选完整保留。在详情里显示四组关键信息，覆盖范围继续可展开。摘要列表只在标题下显示一次发件人和时间，阅读区「查看原文」定位正文 |
| U4 整理完成态 | 已应用任务仅显示完成数量、详情、撤销和再次整理。详情为独立分页列表；再次整理先展开参数，不立即运行。运行与待审阅状态继续显示进度和控制 |
| U5 AI 动作 | 工具栏的整封理解入口只打开面板；附件区重复入口已在后续修整中移除。翻译先显示已有译文或“生成译文”；旧纯文本译文保留，手动重新翻译恢复排版。回复态度、语气和长度仅选择，写信及回复共用参数控件；明确生成、重新生成、采用和发送各自独立 |
| U6 活动记录 | 按账户展示最近同步结果与当前未完成文件夹、错误；只有实际任务进行中才显示“正在同步”。同步历史按需展开，同账户相同无变化结果再次折叠，原始事件逐项保留可查，装饰图标不重复宣布进行中状态 |

<a id="r1-r5-current"></a>
## 工作台与辅助面板

### 工作区视觉与编辑面板

2026-11-17 根据用户确认的“更接近 Filo”方向完成首轮精修，随后修正重复入口、日期时间、助手输入与 AI 阅读。两轮审查和当轮验证分别见 [R1-R5 界面精修记录](research/R1_R5_UI_REFINEMENT_2026-11-17.md)与[交互修整记录](research/R1_R5_INTERACTION_REFINEMENT_2026-11-17.md)。保留系统字体、现有蓝色及原生分栏，跟进、规则、发送管理、助手和附件中心改为白色工作面；辅助容器使用浅灰，主操作和选择使用蓝色。

- `WorkspaceHeader` 使用 22 pt semibold 标题、12 pt 辅助说明与 8 pt 间距，操作组与标题对齐，宽度不足时换行。页面分组间距为 20 或 24 pt，外围仍为 28 pt。
- 跟进、规则及发送清单复用无外框的 `WorkspaceList`，内容内边距 16 或 20 pt，行间轻分隔。附件表格继续保留表头、轻边框与固定分页栏。空清单使用对应空态，不呈现空白列表框。
- 规则的查询表单使用 `MailQueryEditor`。账户与文件夹、状态与分类各占一列，搜索条件独占一行。字段高 36 pt，组内间距 16 pt，搜索语法按需展开。规则表单内容上限为 768 pt，按说明、条件、邮件动作、AI 处理与运行方式分组，内容滚动，提交栏固定。
- 跟进编辑与搜索、定时发送共用月历，日期之外增加原生时间字段；标题、来源和行动分层，底部复用 `SettingsActionBar`。写作语言、风格和签名复用现有输入与原生下拉，管理风格为独立浮层。
- 助手右栏顶部同排放置标题、新建问答、历史和收起按钮。下一行显示一个文件夹菜单，按需切换查阅范围。对话在右栏内部滚动。输入区横跨右栏，发送和快捷键菜单收在下方靠右，回答期间在同一位置显示停止按钮。整条来源栏打开带独立滚动的浮层。邮件主题和日期同排，账户只在跨账户时逐条显示。
- 附件中心只保留文件列表，原邮件与发件人直接放在文件行，不另建来源邮件列表。行首圆形选择控件用于附件比较，文件类型图标位于名称前；已选状态、数量、清除和比较操作保持可见。开始比较会打开新问答，可直接输入需要比较的内容。
- 搜索、写信、发送管理与跟进共用 `CalendarMonthView`；`DateTimeSelection` 在同一月历下增加时间、快捷预设和时区，换日期时保留时刻。写信与发送管理通过 `SendScheduleForm` 复用这些控件；确认操作保持独立，面板使用白色表面。

### 功能与状态

- 邮件查询由 `MailQuery` 统一描述账户、文件夹、关键词、状态与分类；发件人聚合和概要显示作为单独偏好。账户菜单的“所有账户”只作用于支持统一范围的邮件列表，其他工作区仍显示实际账户。行与阅读区保留来源账户。
- 分类菜单包含全部及未分类，并显示完整查询计数。分类管理用实色色点识别标签，新增时预选使用较少的颜色，也可用系统取色器自定义。列表和阅读区共用由该颜色得到的标签底色与文字色。已有 AI 概要不触发生成，缺失时显示正文；搜索优先显示命中片段，发件人聚合行明确标为“最新邮件概要”。保存视图从书签入口命名、更新和移除，侧栏可重开。
- 附件中心保留逐文件排序及分页，以及来源条件与清除入口。预览在同封邮件的附件间前后切换；工作区保存分页、滚动和选择。跨邮件比较由用户选文件并说明关系，不按同名推断版本。
- “跟进”独立管理待我处理、等待对方、到期、延后及完成状态。来源、标题和原文期限保留，具体期限由用户确认；已延后的会话暂时不出现在普通收件箱，到期或取消后恢复，不改服务器文件夹。对方回信解除等待提醒，任务仍由用户确认完成。
- 新清单复用 `WorkspaceList`，行内动作保持独立可访问。跟进和定时发送共用月历。跟进的整点控件支持滚动或点击，打开日期浮层时编辑暂存值，完成后采用。定时发送保留小时及分钟输入。通知与角标归入“设置 > 常用”，实时同步放入“邮箱同步”；跟进页提供“提醒设置”跳转。未授权通知不影响应用内清单。
- “规则与用量”区分规则、处理记录和 AI 用量。规则保存意图及结构化条件，先预览命中、原因及动作，再确认执行；支持定向重试、暂停和撤销邮件状态。自动规则按创建顺序处理新邮件，跟进建议及回复预览仍需审阅。
- 写信 AI 区保存语言、风格和账户签名。选区及整篇候选均明确替换范围，采用走 TextKit 撤销；正文或格式已修改时，旧候选不能覆盖编辑。切换发件账户保留当前正文，签名保存用于后续新建和回复。
- “发送管理”展示等待、提交中、已发送、失败、结果不确定和取消。普通发送确认后等待 10 秒；定时入口显示日期、时区和本机运行条件。等待时可取消回草稿或改期，SMTP 提交后不再显示撤销投递。
- 邮件助手的新问答默认使用当前文件夹，在其他工作区默认使用收件箱。切换文件夹会启动新问答，保留未发送的问题。阅读区的邮件和会话入口、附件中心的比较入口沿用各自选择的来源。助手先在本机检索，再按模型预算选取正文、可读附件片段和最近对话。回答经 AI SSE 逐步显示，来源校验通过后连同引用和覆盖情况一起保存。停止会取消本轮请求，保留先前对话。发送按钮标出 Return 或 Command + Return，分别用 Shift + Return 或 Return 换行，中文输入法确认候选仍由原生编辑器处理。建议动作须经审阅，来源可直接打开。

隔离原生检查覆盖已保存视图、跟进编辑、规则预览／运行／撤销、助手范围、写作参数、发送时间和附件来源。模型问答与自动处理使用合成或模拟服务回归；真实服务验证范围见 CHANGELOG。

## 后续 UI / UE 方案（未实现）

R1-R5 的原方案已经按上方实际交互更新。D6 周期 AI 任务与 D7 本地 MCP 仍为候选；正式分发与更新、本机缓存加密及 macOS 邮件入口分别推进，未列入本次交付。

## Do's and Don'ts

### 应当

- 新增界面先查找现有组件，优先复用 `Palette`、`UIType`、`UILayout`、`UIControlSize`、`SettingsFormLayout` 和 `UIMotion`；文字动作、选择项、图标及排序分别使用对应共用控件。
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

以下用于后续 UI 变更的完整验收。2026-11-16 的日常版观察覆盖调研报告 B01 至 B18，后续开发验收按轮次单独记录；这些记录不代表下列尺寸、格式、键盘及辅助功能已全部验证。

- [ ] 主窗口核对 1440 × 900 pt 与 720 × 600 pt、1080 pt 侧栏切换，以及顶部双击缩放的原生动画、历史尺寸恢复和初始最大化默认还原。
- [ ] 邮件列表核对 294、380、560 pt，包含四项筛选、长主题、聚合展开、多选和加载失败。
- [ ] 设置核对 900 pt、写信核对 940 pt 切换前后；底栏、字段、已有抄送和密送保持可见。
- [ ] 核对默认、悬停、按下、聚焦、选中、禁用、处理中、空态和错误状态，确认标签与反馈两侧留白对称、垂直居中且状态切换不移动内容。
- [ ] 附件表格核对 760、960 pt 两侧的展示变化、标题与数据的列起点、操作列中心，以及排序刷新和视口收缩后的整排对齐；对应自动化覆盖 664、900、1246 pt 表格宽度。
- [ ] 摘要核对双列标题、四组关键信息及长待办；主要面板核对小窗口与嵌套呈现、独立表单滚动和固定底栏。
- [ ] 用键盘完成相关流程，检查中文输入法、长收件人、长文件名、长错误文字和 VoiceOver 语义。
- [ ] 开启系统“减少动态效果”，确认位移、展开、底板移动和符号动效按规范降级。
- [ ] 使用开发说明中的隔离验收方式记录受影响场景及验证边界；只对受影响行为运行相应回归。

### AI Markdown 阅读排版

除邮件翻译外，AI 正文使用 `AnalysisDocumentView`，表格和代码块分别由 `AnalysisTableView`、`AnalysisCodeBlockView` 负责，行内样式由 `AITextStyle` 提供。邮件翻译继续保留原邮件结构；结果的阅读排版不改变草稿采用或发送的格式语义。

- 正文 14 pt，行距 6 pt，阅读宽度上限 760 pt；一级、二级、其他标题分别为 22、18、15 pt semibold。
- 标题前后间距分别为 26、10 pt，连续列表项间距 7 pt，其他内容块间距 16 pt。引用使用 1 pt 中性线，不额外套卡片。
- 表格按可用宽度分配等宽列，每列至少 144 pt，窄面板内横向滚动；表头使用中性浅底，行间使用细分隔线。
- 代码块保留空白、等宽字体和横向滚动，顶栏显示语言与复制动作；行内代码使用浅底。正文可选择复制，链接沿用现有外部链接处理。
- 摘要收起时显示三行清理后的预览，展开后使用完整 Markdown 排版。回复、会话、附件、资料包、邮件问答和比较结果共用上述渲染；主题和操作名称保持其原有控件角色。原始 Markdown 附件共用标题、正文和表格样式，按原文件结构解析。
- 对话在底部时跟随新增内容；用户向上滚动后保持阅读位置，回到底部继续跟随。新提问进入当前回答位置。
