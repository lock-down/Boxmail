export class ServiceError extends Error {
  constructor(message, status = 400) {
    super(message);
    this.status = status;
  }
}
export function required(value, label, max = 500) {
  if (typeof value !== 'string' || !value.trim() || value.length > max)
    throw new ServiceError(`${label}无效`);
  return value.trim();
}
export function accountInput(input) {
  const email = required(input.email, '邮箱地址');
  if (!/^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$/.test(email))
    throw new ServiceError('请输入有效的邮箱地址');
  for (const field of ['imapPort', 'smtpPort'])
    if (
      !Number.isInteger(input[field]) ||
      input[field] < 1 ||
      input[field] > 65535
    )
      throw new ServiceError('端口必须为 1–65535');
  return {
    id: input.id,
    name: required(input.name || email, '账户名称'),
    email,
    username: required(input.username || email, '用户名'),
    imapHost: required(input.imapHost, 'IMAP 地址'),
    imapPort: input.imapPort,
    imapTLS: input.imapTLS !== false,
    smtpHost: required(input.smtpHost, 'SMTP 地址'),
    smtpPort: input.smtpPort,
    smtpTLS: input.smtpTLS !== false,
    lastSync: null,
    isDemo: false,
  };
}
export function recipients(input) {
  const addresses = String(input || '')
    .split(/[,;，；\n]/)
    .map((v) => v.trim())
    .filter(Boolean);
  if (addresses.some((a) => !/^([^\s@<>]+)@([^\s@<>]+)\.[^\s@<>]+$/.test(a)))
    throw new ServiceError('收件人地址格式不正确，请用逗号分隔');
  if (addresses.length > 100) throw new ServiceError('收件人数量超过 100');
  return addresses;
}
export function aiConfig(input, { requireModel = true } = {}) {
  const url = new URL(required(input.baseURL, 'API 地址'));
  if (
    url.protocol !== 'https:' &&
    !(
      url.protocol === 'http:' &&
      ['localhost', '127.0.0.1', '[::1]'].includes(url.hostname)
    )
  )
    throw new ServiceError('API 地址必须使用 HTTPS，本地服务可使用 HTTP');
  if (url.username || url.password || url.search || url.hash)
    throw new ServiceError('API 地址不能包含凭证、查询参数或片段');
  return {
    baseURL: url.href.replace(/\/$/, ''),
    model: requireModel
      ? required(input.model, '模型名称')
      : String(input.model || '')
          .trim()
          .slice(0, 500),
    timeout: Math.min(180, Math.max(10, Number(input.timeout) || 60)),
    maxTokens: Math.min(16000, Math.max(256, Number(input.maxTokens) || 4096)),
    temperature: Math.min(2, Math.max(0, Number(input.temperature) || 0)),
    tokenParameter:
      input.tokenParameter === 'max_tokens'
        ? 'max_tokens'
        : 'max_completion_tokens',
    enabled: input.enabled !== false,
    prompts: Object.fromEntries(
      Object.entries(input.prompts || {})
        .filter(
          ([k, v]) =>
            ['summary', 'reply', 'classify', 'attachment', 'compose'].includes(
              k,
            ) && typeof v === 'string',
        )
        .map(([k, v]) => [k, v.slice(0, 6000)]),
    ),
  };
}
