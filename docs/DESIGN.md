---
name: Boxmail coss UI
description: 原生 macOS 邮件客户端的界面与交互规范。
colors:
  background: "#FFFFFF"
  foreground: "#20201F"
  chrome: "#F5F5F4"
  sidebar: "#F4F4F2"
  muted: "#F8F8F7"
  muted-foreground: "#62615D"
  primary: "#252522"
  primary-foreground: "#FFFFFF"
  accent: "#5145BC"
  accent-soft: "#EFEDFF"
  selected: "#E8E7E3"
  border: "#D6D5D2"
  separator: "#E9E8E5"
  success: "#22674D"
  warning: "#805318"
  destructive: "#AE322D"
typography:
  title: { fontFamily: "system", fontSize: "24pt", fontWeight: 600 }
  heading: { fontFamily: "system", fontSize: "17pt", fontWeight: 600 }
  section: { fontFamily: "system", fontSize: "14pt", fontWeight: 600 }
  body: { fontFamily: "system", fontSize: "13pt", fontWeight: 400 }
  caption: { fontFamily: "system", fontSize: "12pt", fontWeight: 400 }
  small: { fontFamily: "system", fontSize: "11pt", fontWeight: 400 }
rounded:
  minimum: "4pt"
  frame: "20pt"
  card: "24pt"
  control: "8pt"
  navigation: "8pt"
  list-row: "12pt"
  menu: "12pt"
  segmented: "12pt"
  web-control: "12px"
  web-panel: "16px"
  web-frame: "20px"
  web-brand-compact: "40px"
  web-brand-medium: "48px"
  web-brand-large: "64px"
spacing:
  window-frame: "12pt"
  page: "24pt"
  section: "16pt"
  control-gap: "4pt"
---

# Boxmail coss UI 设计规范

本文对应 Boxmail 0.1.12（build 51）。

## 设计方向

收件箱打开后，账户和文件夹在左侧，邮件列表居中，阅读区占主要空间。顶栏负责全局搜索和窗口级操作。写信、发送和保存用深色实心按钮，列表选择用中性底色和描边，靛色用于未读、链接和键盘焦点。工作区的表格与页脚放进同一个细边框，正文保留整块白色阅读面。

应用内界面以 coss UI 为组件规范，由 SwiftUI 和 AppKit 实现。原生文本输入、辅助功能、窗口管理、系统文件面板和 Quick Look 提供 macOS 能力。邮件正文和附件原件按来源格式呈现。本文尺寸使用 pt，配色对应客户端的浅色外观。[coss 样式](https://coss.com/ui/docs/styling)

产品功能与操作名称以使用指南为准，发布历史见变更记录。[使用指南](USER_GUIDE.md) · [变更记录](../CHANGELOG.md)

## UI 组件参考

每次新增、修改或审查 UI，先查 coss UI 的官方组件索引，再读对应组件的说明、示例和实现。核对组件的结构、尺寸、状态、键盘行为与辅助功能语义。优先复用项目里的共用控件，已有控件缺少所需组合时，在共用组件中补齐。[coss UI 官方组件索引（llms.txt）](https://coss.com/ui/llms.txt)。coss UI 官方示例组件使用文档(https://coss.com/ui/docs)

上游提供的单个控件用于匹配的交互，时间和颜色等复合控件用索引中的原语组合。验收同时检查触发器、展开内容、输入后的值和关闭行为。系统面板通过 coss 样式的应用内入口打开。

## 图标

应用与官网的界面图标统一使用 Appica Icons 1.1.0。普通操作及导航用线框版，星标、收藏等已选状态用填充版。原始线框在 24 × 24 画布上的线宽为 1.5。图标跟随控件颜色，独立图标按钮保留可访问名称。Dock、Finder、网站 favicon 和侧栏品牌标识使用 Boxmail 品牌图。[Appica 使用文档](https://appica.dev/ui/icons/react.md) · [Appica 1.1.0 源文件](https://github.com/appica-dev/appica-icons/tree/react%401.1.0/assets)

客户端在 `AppicaGlyph` 声明资源名，由 `AppicaIcon` 渲染本地 SVG。导航、按钮和工具栏图标默认 18 pt，紧凑状态图标 16 pt，展开箭头 14 pt，复选框内的勾号 12 pt。官网默认 24 px，按钮与链接常用 20 px，较小的辅助图标 18 px。官网使用同版 SVG 符号，App 和官网各自附带 MIT 许可。[客户端图标实现](../Sources/Boxmail/Support/AppicaIcon.swift) · [MIT 许可](../Sources/Boxmail/Resources/AppicaIcon/LICENSE.txt)

## 圆角与嵌套间距

以 4 为网格组织圆角及相接的留白，内圆角取 `max(4, 外圆角 − 内缩)`。原生工作区外框 20 pt，内缩 8 pt 的列表行取 12 pt。卡片和宽浮层 24 pt，内缩 16 pt 的字段与按钮取 8 pt。菜单和分段槽为 12 pt，内缩 4 pt 的选项取 8 pt。导航项内缩 12 pt 时取 8 pt。原生端使用 SwiftUI 的连续圆角，圆形头像和胶囊开关使用对应原生形状。系统窗口和系统面板的外轮廓由 macOS 绘制。

官网保留 `border-radius`，在支持 `corner-shape` 的浏览器应用 `superellipse(1.25)`。移动导航外框 16 px，内缩 8 px，菜单项为 8 px。标注圆点和图标外的圆环使用 `round`。

| 原生 App 元素 | 旧值 → 新值（pt） |
| --- | --- |
| 主工作区、WorkspaceList 边框 | 12 → 20 |
| SectionCard、草稿卡片、清单卡片和规则页状态卡 | 12 → 24 |
| 写信工具、搜索、改期、日历等常规浮层 | 12 → 24 |
| 表格行、邮件行 | 8 → 12 |
| 命令菜单、收件人建议、分段槽、空态图标底板 | 8 → 12 |
| 按钮、字段、图标按钮、分段选中项、菜单项、联系人建议项、日历日期及提示气泡等标准控件 | 6 → 8 |
| 收件信息卡、侧栏品牌标识裁切 | 7 → 8 |
| 标签、邮件列表总数 | 6 → 4 |
| 菜单色板色样 | 3 → 4 |
| 键盘焦点外轮廓，常规控件、导航、直角行 | 9 / 11 / 3 → 12 / 12 / 4 |
| 开关轨道、圆形滑块 | 9 / 7 → 12 / 8 |
| 本机表格预览卡片（WebKit） | 6 → 8 px |
| 邮件与附件预览滚动条滑块（WebKit） | 3 px → 胶囊 |

| 官网元素 | 旧值 → 新值（px） |
| --- | --- |
| 应用预览框 | 8 → 20 |
| 首屏预览框上角 | 8 → 20 |
| 上下文来源卡、数据说明 | 6 → 16 |
| 上下文核心、本机数据框、模型服务框、移动导航 | 8 → 16 |
| 移动端上下文输出卡 | 0 → 16 |
| 跳转链接、下载按钮、移动菜单开关 | 6 → 12 |
| 首屏预览切换按钮 | 4 → 12 |
| 工作流选项（普通 / 选中及移动端） | 0 / 6 → 12 |
| 移动导航链接 | 4 → 8 |
| 下载区品牌图裁切（中屏 / 小屏） | 50 / 42 → 48 / 40 |

## 颜色与排版

| 用途 | 规范 |
| --- | --- |
| 内容与导航 | 邮件、列表和编辑区用白底。窗口与侧栏采用相邻的暖中性色，工作区辅助表面用 muted。 |
| 文本 | 标题与正文用 foreground，元数据、字段说明和次级图标用 muted foreground。日期和数量用等宽数字。 |
| 主次操作 | 提交动作用 primary 和白字。次要动作用白底描边，工具栏和取消用透明底，悬停时加入中性填充。 |
| 选中与焦点 | 导航和行选择用 selected 或 accent soft。文字加字重、勾选状态或原生选中语义。键盘焦点用靛色轮廓。 |
| 状态 | 成功、待确认和失败分别使用 success、warning、destructive，连同状态名称、图标或可执行操作呈现。分类使用已有分类名和配色。 |
| 尺寸与形态 | 卡片圆角 24，工作区 20，列表行 12，标准按钮与字段 8。边线 1，浮层使用原生层级，普通内容由边线和留白组织。 |

界面字体使用系统无衬线和中文回退。工作区标题 24，面板标题 17，分组标题 14，普通界面文字 13，列表预览及说明 12，日期和计数 11。邮件主题在阅读区单独使用 22，正文沿用用户字号设置。长主题、错误说明和操作结果可以换行，列表里的长文件名和地址保留完整值供查看。

## 窗口与导航

| 区域 | 布局 |
| --- | --- |
| 主窗口 | 默认 1440 × 900，最小 720 × 600。顶部留原生拖动区，保留双击缩放与还原。 |
| 顶栏 | 高 52。全局搜索与组合条件入口居中，右侧是同步、活动和设置。搜索条件、账户范围与返回来源在对应工作区可见。 |
| 导航 | 窗口宽度达到 1080 时显示 216 宽的侧栏。窄窗口从左侧打开导航抽屉。写信是侧栏的主操作，账户选择器位于邮箱组之前。文件夹和已保存视图各自分组。 |
| 内容框 | 主工作区的外框距窗口右边和下边各 12。窄窗口两边均留 12，带常驻侧栏时，框左边界与侧栏相邻。将正文、列表和页脚沿直线分隔。 |
| 邮件分栏 | 邮件列表可拖动，宽度 294 至 560，理想宽 380。阅读区最小 400，内容宽度上限 860。 |

## 组件

| coss 模式 | Boxmail 实现与用法 |
| --- | --- |
| Button / Toolbar / Tooltip | ActionButton、IconButton 及共用反馈。控件高 28、32、36，图标按钮有可访问名称。实心提交、描边次操作、透明工具栏按钮按用途组合。 |
| Input / Input Group / Field | 搜索采用搜索图标、输入和清除按钮的组合。表单字段使用白底描边、有焦点反馈，标签、说明和字段错误紧邻输入。编辑器保留原生输入法、选区和快捷键。 |
| Select / Menu / Context Menu | 值选择、命令和右键菜单共用白底浮层、细边框、分组和菜单项。当前值显示勾选，独立开关显示复选状态，子菜单向侧面展开。键盘可用方向键浏览、回车选取、Esc 关闭。 |
| Popover / Autocomplete | 组合搜索、日历、来源和写信工具使用无箭头的白底圆角浮层。弹层贴近触发器并避开屏幕边缘，收件人建议跟随输入位置。 |
| Date Picker / Calendar / Number Field | 搜索日期由字段触发 Calendar 浮层，选择日期后回填原表单。定时发送和改期共用日历与小时、分钟数字输入，跟进提醒用可滚动的 Select 选整点。 |
| Toolbar / Slider / Input Group | 写信使用分组格式工具栏。字号菜单显示当前值和混合状态。自定颜色和分类颜色共用色值输入、RGB 滑杆和数字输入。 |
| Tooltip / Spinner / Separator | 图标和截断内容用锚定的 Tooltip。等待状态用 Spinner，分组边线共用 Separator。 |
| Segmented Control / Tabs / Toggle | 邮件筛选的分段控件使用浅底槽与白底选中项。清单状态用菜单单选项，事项完成状态用带标题的复选框。 |
| Frame / Table / Pagination | SectionCard 和 WorkspaceList 提供分组边框、内容区和固定页脚。收件箱、压缩包目录和规则记录共用表格行的圆角、悬停、选中及间距，保留键盘选择语义。 |
| Dialog / Drawer | 设置、写信、预览、配置导入与确认使用标题、可滚动内容和固定操作区。破坏性确认用红色按钮，取消用透明按钮。窄窗导航使用左侧抽屉。 |
| Checkbox / Switch / Progress | 表单和菜单复选项共用方形勾选控件。开关使用胶囊轨道，可量化任务使用细进度条。 |
| Badge / Empty / Alert / Toast | 标签显示分类或状态。空态保留必要的标题、说明和可选动作。失败信息提供原因与恢复入口。手动邮件操作通过可关闭的状态提示提供撤销。 |

[coss Button](https://coss.com/ui/docs/components/button) · [Input](https://coss.com/ui/docs/components/input) · [Frame](https://coss.com/ui/docs/components/frame) · [Segmented Control](https://coss.com/ui/docs/components/segmented-control) · [Drawer](https://coss.com/ui/docs/components/drawer) · [Menu](https://coss.com/ui/docs/components/menu) · [Select](https://coss.com/ui/docs/components/select) · [Table](https://coss.com/ui/docs/components/table) · [Date Picker](https://coss.com/ui/docs/components/date-picker) · [Number Field](https://coss.com/ui/docs/components/number-field) · [Toolbar](https://coss.com/ui/docs/components/toolbar) · [Slider](https://coss.com/ui/docs/components/slider)

## 邮件阅读与处理

- 列表标题显示当前视图和条目数，筛选位于标题下方。邮件行依次显示发件人、主题与预览，右侧列放时间和状态。未读以字重和靛色圆点表示，选中底色覆盖整行，行面之间保留小间距。同一发件人的折叠、已读、多选及批量操作遵循原列表行为。
- 阅读区顶栏提供回复、转发和邮件操作。主题、标签及收件信息之后是正文。翻译主按钮与设置菜单组成 Group，用分隔线区分操作，语言用菜单单选，Auto 用复选项。正文标题、复制、进度和重试紧邻控件。 [coss Group](https://coss.com/ui/docs/components/group) · [Menu](https://coss.com/ui/docs/components/menu)
- 有旧结果时，更多邮件操作才显示「历史结果…」。会话结论、问答及整封分析使用折叠段落，来源可返回对应邮件或预览。 [coss Dialog](https://coss.com/ui/docs/components/dialog) · [Collapsible](https://coss.com/ui/docs/components/collapsible)
- 附件卡片显示文件名和大小。预览操作含原邮件、打开原文件、下载和同封附件切换。已有分析时才提供历史分析选项。

<a id="r1-r5-current"></a>

## 清单、搜索与活动记录

搜索保留范围、组合条件、已保存视图及来源返回。规则编辑入口在设置，处理记录、撤销及 AI 用量在活动记录。待发送邮件的状态显示在草稿卡片中。

清单用 Frame 组织来源邮件，筛选留在标题旁，分页留在边框底部，只有邮件行滚动。先显示可打开原邮件的主题、发件人和时间，再显示概要与事项。跨账户时标明来源账户。事项使用 Checkbox 和 Menu，摘要的移除与恢复在来源行操作。窄窗沿用左侧导航抽屉，标题和事项文字可换行。[coss Frame](https://coss.com/ui/docs/components/frame) · [Checkbox](https://coss.com/ui/docs/components/checkbox) · [Menu](https://coss.com/ui/docs/components/menu) · [Pagination](https://coss.com/ui/docs/components/pagination)

收件箱筛选采用 Menu 单选项。编辑一封邮件的标签用菜单复选项，多选邮件时分别提供添加和移除。邮件行显示一个标签和其余数量，窄列可收起标签文字，通过菜单读取完整清单。整理邮件和标签试用共用选信对话框，正文区滚动，底栏显示选中数量和主要操作。试用结果展示命中的邮件，点「应用标签」后保存。[coss Menu](https://coss.com/ui/docs/components/menu) · [Checkbox Group](https://coss.com/ui/docs/components/checkbox-group) · [Dialog](https://coss.com/ui/docs/components/dialog)

### ZIP 与来源预览

文件目录可独立滚动，条目显示名称、路径和大小。选中文件先展示原件，已有分析时可切换查看。已有 ZIP 整体分析提供依据文件链接。

## 写信与设置

收件人、主题、格式栏和正文依次排列。「帮我写」从格式栏打开右对齐的浮层，选区右键打开同一入口。写作要求和生成按钮直接可见。「写作选项」收起时显示当前风格和语言，整行点击展开为两个选择行。风格菜单分为内置风格和我的风格，并在当前值旁显示语气和篇幅。自定义页集中调整语气、篇幅和行文要求，可仅用于当前写信窗口或保存为预设。输出语言沿用翻译菜单的语言选项，默认根据来信、待改写文本或写作要求选取。候选在同一浮层预览，较长的候选可滚动，修改要求和采用按钮留在底部。关闭后焦点回到正文。 [coss Popover](https://coss.com/ui/docs/components/popover) · [Textarea](https://coss.com/ui/docs/components/textarea)

签名可在账号设置配置。写信时「签名」标签和分隔线标出正文与签名的边界。点击空白处可回到正文末尾，点击签名文字可定位到对应行。草稿有签名时，采用完整候选后光标留在签名前的正文空行。发送内容为连续的正文与签名。写信底栏保留附件、草稿状态、定时发送和发送确认。设置在 900 pt 及以上显示侧边导航，窄窗使用顶部分类。 [coss Fieldset](https://coss.com/ui/docs/components/fieldset) · [Select](https://coss.com/ui/docs/components/select) · [Collapsible](https://coss.com/ui/docs/components/collapsible) · [Context Menu](https://coss.com/ui/docs/components/context-menu) · [Dialog](https://coss.com/ui/docs/components/dialog)

## 键盘、辅助功能与验收

- 在 1440 × 900 和 720 × 600 窗口检查工作区边缘、导航、邮件分栏、写作浮层及底部操作。检查侧栏在 1080 pt 两侧的表现与上下文恢复。
- 检查键盘聚焦、Tab 导航、Esc、列表多选和既有快捷键。编辑框的输入法和系统文字快捷键由原生控件处理。图标按钮提供可访问名称，筛选和选中行提供状态语义。
- 检查默认、悬停、选中、聚焦、禁用、加载、空态和失败。检查长主题、地址、附件名、来源及错误说明。开启减少动态效果时，抽屉和选中底板直接更新。
- 使用隔离演示数据检查收件与搜索、写信和设置、附件预览和历史结果、清单、规则与草稿箱。核对搜索日期回填、定时发送的时分输入、清单提醒整点、字号和选区颜色。记录实际检查范围和自动化回归结果。

共用实现见 [DesignSystem.swift](../Sources/Boxmail/Support/DesignSystem.swift)、[ControlStyle.swift](../Sources/Boxmail/Support/ControlStyle.swift) 和 [ContentView.swift](../Sources/Boxmail/Views/ContentView.swift)。构建和联调方式见 [开发说明](DEVELOPMENT.md)。
