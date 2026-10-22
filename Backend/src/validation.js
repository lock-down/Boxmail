import { DEFAULT_PROMPTS } from './ai-settings.js';

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
const ADDRESS_PATTERN = /^[^\s@<>,;，；]+@[^\s@<>,;，；]+\.[^\s@<>,;，；]+$/;
const RECIPIENT_ERROR = '收件人地址格式不正确，请用逗号分隔';
const CONTROL_CHARACTER_PATTERN = /[\u0000-\u001f\u007f]/;
const QUOTED_DISPLAY_PATTERN = /^"((?:[^"\\]|\\.)*)"\s*<([^<>]*)>$/;
const SIMPLE_DISPLAY_PATTERN = /^([^<>",;@\\]+?)\s*<([^<>]*)>$/;
// 联系人补全写入的是 RFC 5322 的 `"姓名" <email>`；切分时若在双引号（含转义）
// 或尖括号内，则不把逗号/分号/换行（CRLF 或 LF）当作分隔符。
function splitRecipientTokens(value) {
  const tokens = [];
  let token = '';
  let quoted = false;
  let angled = false;
  let escaped = false;
  for (const character of value) {
    if (quoted && escaped) {
      token += character;
      escaped = false;
    } else if (quoted && character === '\\') {
      token += character;
      escaped = true;
    } else if (character === '"') {
      token += character;
      quoted = !quoted;
    } else if (!quoted && character === '<') {
      token += character;
      angled = true;
    } else if (!quoted && character === '>') {
      token += character;
      angled = false;
    } else if (!quoted && !angled && ',;，；\n\r'.includes(character)) {
      tokens.push(token);
      token = '';
    } else {
      token += character;
    }
  }
  tokens.push(token);
  return tokens;
}
function parseAddressToken(token) {
  if (ADDRESS_PATTERN.test(token)) return token;
  const quoted = QUOTED_DISPLAY_PATTERN.exec(token);
  if (quoted) {
    const name = quoted[1].replace(/\\(.)/g, '$1');
    if (!name.trim() || !ADDRESS_PATTERN.test(quoted[2])) return null;
    return `"${name.replace(/\\/g, '\\\\').replace(/"/g, '\\"')}" <${quoted[2]}>`;
  }
  const simple = SIMPLE_DISPLAY_PATTERN.exec(token);
  if (!simple) return null;
  const name = simple[1].trim();
  if (!name || !ADDRESS_PATTERN.test(simple[2])) return null;
  return `"${name}" <${simple[2]}>`;
}
export function recipients(input) {
  const addresses = [];
  for (const raw of splitRecipientTokens(String(input || ''))) {
    if (CONTROL_CHARACTER_PATTERN.test(raw))
      throw new ServiceError(RECIPIENT_ERROR);
    const token = raw.trim();
    if (!token) continue;
    const address = parseAddressToken(token);
    if (!address) throw new ServiceError(RECIPIENT_ERROR);
    addresses.push(address);
  }
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
  const effort = input.effort ?? 'high';
  if (!['low', 'high', 'max'].includes(effort))
    throw new ServiceError('思考等级只能选择 Low、High 或 Max');
  return {
    baseURL: url.href.replace(/\/$/, ''),
    model: requireModel
      ? required(input.model, '模型名称')
      : String(input.model || '')
          .trim()
          .slice(0, 500),
    timeout: Math.min(600, Math.max(10, Number(input.timeout) || 120)),
    effort,
    enabled: input.enabled !== false,
    prompts: Object.fromEntries(Object.entries(DEFAULT_PROMPTS).map(([task, fallback]) => {
      const custom = input.prompts?.[task];
      return [task, typeof custom === 'string' && custom.trim() ? custom.trim().slice(0, 6000) : fallback];
    })),
  };
}
