# Product

<!-- impeccable:product-schema 1 -->

## Platform

macos

## Users

Boxmail 优先服务每天用 Mac 处理多个邮箱的用户。他们需要在同一个地方读信、回复和跟进，换邮箱时也能找到尚未处理的事项。

## Product Purpose

让邮件里需要处理的事进入「待办清单」。用户能看到哪些邮件需要回复或继续跟进，打开原信核对，完成事项或设定提醒。标签、规则和 AI 优先用于减少漏跟进。

## Positioning

Boxmail 把通用 IMAP/SMTP 多账户收发、本机中文全文搜索和按来源邮件组织的待办清单放在同一个 macOS 客户端。清单合并 AI 提取的事项和手工跟进，每项都可返回来源邮件。用户可以在原有邮箱上使用这些流程，并自行选择 AI 服务商和模型。

## Operating Context

- 在不同账户间读信和回复，通过引用链查看会话，用中文全文、附件内容、标签或已保存视图找回邮件。
- 在「待办清单」按来源查看摘要与待办，手工添加跟进或提醒。整理可从选中的邮件开始，也可按邮箱授权自动处理新信。规则设定前可核对样例和适用范围，批次结果及规则执行情况可在「活动记录」查看。
- 在原邮件阅读区翻译，在写信窗口使用「帮我写」生成可采用的候选。待发送邮件留在草稿箱，可继续编辑、改期或取消。

## Capabilities and Constraints

- 1.0.0 安装包适用于 Apple Silicon。原生客户端声明最低 macOS 14。
- 邮件、附件、索引和 AI 结果保存在本机，可迁移数据目录及备份恢复。同步和发信连接用户配置的邮箱服务器。应用以未加密的形式保存本机缓存、凭证文件和完整备份。
- AI 使用用户配置的 API 密钥，支持 OpenAI Responses、OpenAI Chat Completions 和 Anthropic Messages。调用云端模型时，任务所需内容会提交给所选服务商。翻译、整理和写作的具体提交范围见 [邮件 AI 上下文](docs/MAIL_AI_CONTEXT.md)。
- 「待办清单」「整理助手」「邮箱规则」「活动记录」和「帮我写」是现有操作名称。涉及收件箱分类和筛选时使用「标签」。

## Brand Commitments

产品名称为 Boxmail，沿用现有 [品牌图标](Sources/BoxmailCore/Resources/BoxmailMark.png)。

## Evidence on Hand

- 操作和已验证范围见 [使用指南](docs/USER_GUIDE.md)，原生验收及合成数据的适用范围见 [开发说明](docs/DEVELOPMENT.md)。
- 官网独立发布，演示截图使用合成邮件。对外展示的功能、截图和下载入口以对应的公开安装包为准。[发布维护说明](docs/DEVELOPMENT.md#文档与本地产物)

## Product Principles

- 优先让用户看见还需要处理什么，给每个事项保留返回原邮件的入口。
- 自动处理以邮箱授权和用户确认过的规则范围为准。保留人工修改，给用户核对处理结果的入口。
- 写作候选由用户采用，邮件发送由用户确认。
- 保留用户对本机数据和 AI 服务的选择权，说明每项 AI 功能会提交哪些邮件内容。

## Accessibility & Inclusion

保留邮件列表的原生键盘导航、多选和常用命令快捷键，为控件提供可访问名称。现有验收检查了辅助功能树，VoiceOver 全流程仍待专项验证。[使用指南](docs/USER_GUIDE.md#列表多选与快捷键) · [开发说明](docs/DEVELOPMENT.md#邮件与工作区状态)
