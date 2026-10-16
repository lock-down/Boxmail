# 钥匙串授权与开发签名

Boxmail 把 API Key 和邮箱授权码保存在 macOS 钥匙串。弹窗中的密码指“登录”钥匙串的密码，通常是 Mac 的登录密码。

## 当前弹窗如何处理

在 Boxmail 主动执行 AI 或同步操作时，由用户在系统弹窗中输入 Mac 登录密码并点击“始终允许”。“允许”只授权本次读取，之后仍可能询问。API Key 和邮箱授权码属于不同钥匙串项目，可能分别要求授权。[Apple 授权说明](https://support.apple.com/en-gb/guide/mac-help/kychn002/26/mac/26)解释了这两个选项的区别。

应用成功取得凭证后仅在当前进程内存中复用。修改或清空凭证会在钥匙串写入成功后更新缓存，写入失败保留原值；退出时清空内存。未授权或读取失败不会缓存成成功结果，用户可以主动重试。

后台同步只使用本次运行中已经读取或保存的邮箱凭证。重启后首次后台同步若没有凭证缓存，侧栏显示“邮箱需授权 · 点击同步”；点击后由用户完成授权，此后的后台同步复用缓存。打开常用、账号等设置页不会顺带读取 AI 密钥，保存未修改的 API Key 也不会重复写入钥匙串。

## 为什么重新构建后还会出现

默认构建使用 `codesign --sign -` 临时签名。实际检查发现 App 的指定要求为 `cdhash`，它会随代码变化。因此固定 Bundle ID 并不足以让系统跨重编译识别相同应用。[Apple TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)说明了临时签名与固定签名身份的差异。

2026-10-16 检查时，本机没有可用的代码签名身份。当前构建保留临时签名，并在构建输出提示此限制。

## 使用固定签名证书

先准备可用且带私钥的代码签名证书，例如 Apple Development 或 Developer ID Application。每次构建使用同一身份和 Bundle ID，可让系统识别应用更新；第一次切换证书后仍可能需要重新选择“始终允许”。正式分发还需单独完成签名与公证流程。

列出本机可用身份：

```bash
security find-identity -v -p codesigning
```

使用其中证书的 SHA-1 指纹构建：

```bash
BOXMAIL_SIGNING_IDENTITY="证书的 SHA-1 指纹" ./script/build_and_run.sh --verify
```

要让 Codex 的 Run 按钮和后续构建一直使用该身份，在仓库根目录创建 `.boxmail-signing-identity`，仅写入该指纹一行。此文件已被 Git 忽略。环境变量优先于文件；没有配置时使用临时签名。证书私钥仍由钥匙串管理，不放入项目。

构建后检查身份：

```bash
codesign -dvvv -r- dist/Boxmail.app
codesign --verify --deep --strict dist/Boxmail.app
```

固定证书签名应显示签名 Authority，指定要求应约束签名者及应用标识，而非仅当前二进制的 `cdhash`。脚本在签名后自动验证 App，签名失败会停止构建流程。

## 验证范围

0.0.4 的 59 项后端测试和 13 项 Swift 测试覆盖已有邮件、AI 功能及凭证缓存行为。系统授权必须由用户在 macOS 弹窗中完成；当前没有固定证书，因此尚未验证跨重编译保留授权。钥匙串访问控制和密钥存储位置沿用原有配置。
