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
  frame: "12pt"
  control: "6pt"
  navigation: "8pt"
  segmented: "8pt"
spacing:
  window-frame: "12pt"
  page: "24pt"
  section: "16pt"
  control-gap: "4pt"
---

# Boxmail coss UI 设计规范

本文对应 Boxmail 0.1.11（build 50）。

## 设计方向

收件箱打开后，账户和文件夹在左侧，邮件列表居中，阅读区占主要空间。顶栏负责全局搜索和窗口级操作。写信、发送和保存用深色实心按钮，列表选择用中性底色和描边，靛色用于未读、链接和键盘焦点。工作区的表格与页脚放进同一个细边框，正文保留整块白色阅读面。

应用内界面以 coss UI 为组件规范，由 SwiftUI 和 AppKit 实现。原生文本输入、辅助功能、窗口管理、系统文件面板和 Quick Look 提供 macOS 能力。邮件正文和附件原件按来源格式呈现。本文尺寸使用 pt，配色对应客户端的浅色外观。[coss 样式](https://coss.com/ui/docs/styling)

产品功能与操作名称以使用指南为准，发布历史见变更记录。[使用指南](USER_GUIDE.md) · [变更记录](../CHANGELOG.md)

## UI 组件参考

每次新增、修改或审查 UI，先查 coss UI 的官方组件索引，再读对应组件的说明、示例和实现。核对组件的结构、尺寸、状态、键盘行为与辅助功能语义。优先复用项目里的共用控件，已有控件缺少所需组合时，在共用组件中补齐。[coss UI 官方组件索引（llms.txt）](https://coss.com/ui/llms.txt)。coss UI 官方示例组件使用文档(https://coss.com/ui/docs)

上游提供的单个控件用于匹配的交互，时间和颜色等复合控件用索引中的原语组合。验收同时检查触发器、展开内容、输入后的值和关闭行为。系统面板通过 coss 样式的应用内入口打开。

## icon 图标参考

应用与官网的界面图标统一使用 Remix Icon。普通操作和导航优先用线框版，已加星标、已完成等状态可用填充版。图标跟随所在控件的文字颜色，单独使用的图标按钮需要有可访问名称。Dock、Finder、站点 favicon 和侧栏品牌标识使用 Boxmail 品牌图。[Remix Icon](https://remixicon.com)

当前使用 Remix Icon 4.9.1 的官方 SVG。客户端在 `RemixGlyph` 声明资源名，由 `RemixIcon` 按点数渲染，常规尺寸为 14 pt。官网的 SVG 符号直接使用同版本路径。新增图标时，从该版本选择对应 SVG 并检查字号、配色及选中状态。[客户端图标实现](../Sources/Boxmail/Support/RemixIcon.swift) · [上游版本](https://github.com/Remix-Design/RemixIcon/tree/v4.9.1)

## 颜色与排版

| 用途 | 规范 |
| --- | --- |
| 内容与导航 | 邮件、列表和编辑区用白底。窗口与侧栏采用相邻的暖中性色，工作区辅助表面用 muted。 |
| 文本 | 标题与正文用 foreground，元数据、字段说明和次级图标用 muted foreground。日期和数量用等宽数字。 |
| 主次操作 | 提交动作用 primary 和白字。次要动作用白底描边，工具栏和取消用透明底，悬停时加入中性填充。 |
| 选中与焦点 | 导航和行选择用 selected 或 accent soft。文字加字重、勾选状态或原生选中语义。键盘焦点用靛色轮廓。 |
| 状态 | 成功、待确认和失败分别使用 success、warning、destructive，连同状态名称、图标或可执行操作呈现。分类使用已有分类名和配色。 |
| 尺寸与形态 | 卡片、工作区和表格外框圆角 12。按钮与字段圆角 6，导航和分段外槽圆角 8。边线 1，浮层使用原生层级，普通内容由边线和留白组织。 |

界面字体使用系统无衬线和中文回退。工作区标题 24，面板标题 17，分组标题 14，普通界面文字 13，列表预览及说明 12，日期和计数 11。邮件主题在阅读区单独使用 22，正文沿用用户字号设置。长主题、错误说明和操作结果可以换行，列表里的长文件名和地址保留完整值供查看。

## 窗口与导航

| 区域 | 布局 |
| --- | --- |
| 主窗口 | 默认 1440 × 900，最小 720 × 600。顶部留原生拖动区，保留双击缩放与还原。 |
| 顶栏 | 高 52。全局搜索与组合条件入口居中，右侧是助手、同步、活动和设置。搜索条件、账户范围与返回来源在对应工作区可见。 |
| 导航 | 窗口宽度达到 1080 时显示 216 宽的侧栏。窄窗口从左侧打开导航抽屉。写信是侧栏的主操作，账户选择器位于邮箱组之前。文件夹、已保存视图和智能工具按任务分组。 |
| 内容框 | 主工作区的外框距窗口右边和下边各 12。窄窗口两边均留 12，带常驻侧栏时，框左边界与侧栏相邻。将正文、列表、页脚和助手沿直线分隔。 |
| 邮件分栏 | 邮件列表可拖动，宽度 294 至 560，理想宽 380。阅读区最小 400，内容宽度上限 860。 |
| 邮件助手 | 360 宽，与邮件列表及阅读区能同时容纳时并排，空间不足时从右侧覆盖。宽屏保留全文阅读宽度，窄屏可用 Esc 或关闭按钮退出。 |

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
| Segmented Control / Tabs / Toggle | 邮件筛选和工作台分段使用浅底槽与白底选中项。可取消的工具模式保留选中反馈，普通操作仍为按钮。 |
| Frame / Table / Pagination | SectionCard 和 WorkspaceList 提供分组边框、内容区和固定页脚。附件、整理结果、摘要、跟进和发送管理共用表格体系。收件箱、压缩包目录和规则记录共用表格行的圆角、悬停、选中及间距，保留键盘选择语义。 |
| Dialog / Drawer | 设置、写信、预览、配置导入与确认使用标题、可滚动内容和固定操作区。破坏性确认用红色按钮，取消用透明按钮。窄窗导航和助手采用边缘抽屉。 |
| Checkbox / Switch / Progress | 表单、附件比较和菜单复选项共用方形勾选控件。开关使用胶囊轨道，可量化任务使用细进度条。 |
| Badge / Empty / Alert / Toast | 标签显示分类或状态。空态保留必要的标题、说明和可选动作。失败信息提供原因与恢复入口。手动邮件操作通过可关闭的状态提示提供撤销。 |

[coss Button](https://coss.com/ui/docs/components/button) · [Input](https://coss.com/ui/docs/components/input) · [Frame](https://coss.com/ui/docs/components/frame) · [Segmented Control](https://coss.com/ui/docs/components/segmented-control) · [Drawer](https://coss.com/ui/docs/components/drawer) · [Menu](https://coss.com/ui/docs/components/menu) · [Select](https://coss.com/ui/docs/components/select) · [Table](https://coss.com/ui/docs/components/table) · [Date Picker](https://coss.com/ui/docs/components/date-picker) · [Number Field](https://coss.com/ui/docs/components/number-field) · [Toolbar](https://coss.com/ui/docs/components/toolbar) · [Slider](https://coss.com/ui/docs/components/slider)

## 邮件阅读与处理

- 列表标题显示当前视图和条目数，筛选位于标题下方。邮件行依次显示发件人、主题与预览，右侧列放时间和状态。未读以字重和靛色圆点表示，选中底色覆盖整行，行面之间保留小间距。同一发件人的折叠、已读、多选及批量操作遵循原列表行为。
- 阅读区先放回复、转发及邮件操作，下一行放整封理解、翻译、AI 回复和会话 AI。主题、分类和收件信息位于正文前。收件人展开后可以独立滚动及复制地址。HTML 正文继承邮件原排版，显示权限仍由邮件阅读规则控制。
- AI 面板先显示已有结果，生成按钮由用户主动触发。AI 内容使用共用 Markdown 排版，表格和代码块各自横向滚动，来源可以返回对应邮件。停止、失败和重试就地显示，滚动位置遵循当前阅读状态。
- 附件文件名和状态采用与附件中心一致的层级。预览支持切换同一来源的文件，原文件和分析各自保留内容区。

<a id="r1-r5-current"></a>

## 工作台、搜索与辅助面板

跟进、摘要、智能整理、规则、发送管理和活动记录共用工作区标题、操作区、内容与分页。首屏显示与任务直接相关的筛选和状态。搜索保留选中的范围、组合条件、已保存视图及来源返回。邮件助手显示当前范围和对话，输入固定在底部，来源和生成进度紧邻回答。

### 附件中心与资料包

名称、日期、大小、来源、状态和操作按可用宽度分配各列。760 和 960 pt 两侧调整辅助列，表头和行使用同一列布局。筛选、排序、分页、双击预览、下载和原邮件跳转沿用同一操作入口。ZIP 预览保留文件列表、单项与整体理解、暂停和重试。

## 写信与设置

写信的收件人、主题、富文本格式栏和正文按阅读顺序布局。抄送、密送、签名、引用、附件和 AI 写作保留既有入口。草稿提交和发送确认用固定底栏，窄窗的 AI 写作从正文旁展开。设置宽度达到 900 pt 显示侧边导航，窄窗改为顶部分类。写信达到 940 pt 并排展示 AI 写作。嵌套对话框按可用窗口大小收缩，失败后保留输入和恢复动作。

## 键盘、辅助功能与验收

- 在 1440 × 900 和 720 × 600 窗口检查工作区边缘、导航、邮件分栏、助手及底部操作。检查侧栏在 1080 pt 两侧的表现与上下文恢复。
- 检查键盘聚焦、Tab 导航、Esc、列表多选和既有快捷键。编辑框的输入法和系统文字快捷键由原生控件处理。图标按钮提供可访问名称，筛选和选中行提供状态语义。
- 检查默认、悬停、选中、聚焦、禁用、加载、空态和失败。检查长主题、地址、附件名、来源及错误说明。开启减少动态效果时，抽屉和选中底板直接更新。
- 使用隔离演示数据检查收件与搜索、写信和设置、附件表格及预览、助手、跟进、摘要、规则与发送管理。核对搜索日期回填、定时发送的时分输入、跟进整点、字号和选区颜色。记录实际检查范围和自动化回归结果。

共用实现见 [DesignSystem.swift](../Sources/Boxmail/Support/DesignSystem.swift)、[ControlStyle.swift](../Sources/Boxmail/Support/ControlStyle.swift) 和 [ContentView.swift](../Sources/Boxmail/Views/ContentView.swift)。构建和联调方式见 [开发说明](DEVELOPMENT.md)。
