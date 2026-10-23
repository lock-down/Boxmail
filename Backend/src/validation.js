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
export const AI_PROTOCOLS = ['openai-responses', 'openai-completions', 'anthropic-messages'];
export const REASONING_LEVELS = ['off', 'minimal', 'low', 'medium', 'high', 'xhigh', 'max'];

export function aiModel(value) {
  if (typeof value === 'string') value = { id: value };
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new ServiceError('模型配置格式不正确');
  const model = { id: modelName(value.id) };
  if (value.name !== undefined) {
    model.name = required(value.name, '模型显示名称', 120);
    if (/[\u0000-\u001f\u007f]/.test(model.name)) throw new ServiceError('模型显示名称不能包含控制字符');
  }
  for (const field of ['contextWindow', 'maxTokens']) {
    if (value[field] === undefined) continue;
    if (!Number.isSafeInteger(value[field]) || value[field] < 1 || value[field] > 2_147_483_647)
      throw new ServiceError('上下文窗口和最大输出 token 数必须为正整数');
    model[field] = value[field];
  }
  if (model.contextWindow && model.maxTokens > model.contextWindow)
    throw new ServiceError('最大输出 token 数不能超过上下文窗口');
  if (value.input !== undefined) {
    if (!Array.isArray(value.input) || !value.input.length || value.input.some(v => !['text', 'image'].includes(v)))
      throw new ServiceError('模型输入类型至少选择文本或图片之一');
    model.input = [...new Set(value.input)];
  }
  if (value.reasoningEfforts !== undefined) {
    if (value.reasoningEfforts === false) model.reasoningEfforts = false;
    else {
      const entries = Object.entries(value.reasoningEfforts || {});
      if (Array.isArray(value.reasoningEfforts) || !entries.some(([level]) => level !== 'off')
        || entries.some(([level, wire]) => !REASONING_LEVELS.includes(level)
          || !(wire === null && level === 'off' || typeof wire === 'string' && wire.trim() && wire.length <= 80 && !/[\u0000-\u001f\u007f]/.test(wire))))
        throw new ServiceError('推理等级需包含至少一个非 Off 等级，且每个等级需填写有效的发送值');
      model.reasoningEfforts = Object.fromEntries(entries.map(([level, wire]) => [level, wire?.trim() ?? null]));
    }
  }
  if (value.compat !== undefined) {
    if (!value.compat || typeof value.compat !== 'object' || Array.isArray(value.compat)) throw new ServiceError('模型兼容性配置格式不正确');
    const compat = {};
    if (value.compat.maxTokensField !== undefined) {
      if (!['max_tokens', 'max_completion_tokens'].includes(value.compat.maxTokensField)) throw new ServiceError('输出上限参数无效');
      compat.maxTokensField = value.compat.maxTokensField;
    }
    if (value.compat.forceAdaptiveThinking !== undefined) {
      if (typeof value.compat.forceAdaptiveThinking !== 'boolean') throw new ServiceError('Anthropic 推理模式无效');
      compat.forceAdaptiveThinking = value.compat.forceAdaptiveThinking;
    }
    model.compat = compat;
  }
  return model;
}

function modelCatalog(values) {
  if (!Array.isArray(values) || values.length > 500) throw new ServiceError('模型目录最多支持 500 个模型');
  const models = values.map(aiModel);
  if (new Set(models.map(m => m.id)).size !== models.length) throw new ServiceError('同一服务商的模型 ID 不能重复');
  return models;
}

function apiURL(value) {
  let url;
  try { url = new URL(required(value, 'API 地址')); }
  catch { throw new ServiceError('请输入有效的 API 地址'); }
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
  return url.href.replace(/\/+$/, '');
}
function apiProtocol(value = 'openai-responses') {
  if (!AI_PROTOCOLS.includes(value)) throw new ServiceError('请选择支持的 API 协议');
  return value;
}
function modelName(value, optional = false) {
  if (optional && (value === undefined || value === '')) return '';
  const name = required(value, '模型名称');
  if (/[\u0000-\u001f\u007f]/.test(name)) throw new ServiceError('模型名称不能包含控制字符');
  return name;
}
export function aiCredentialAccounts(config) {
  return config.providers ? config.providers.map(p => p.id === 'default' ? 'ai-key' : `ai-provider-${p.id}`) : ['ai-key'];
}
export function aiConfig(input, { requireModel = true } = {}) {
  let selected = input, providers;
  let providerId = input.providerId || 'default';
  if (input.providers !== undefined) {
    if (!Array.isArray(input.providers) || !input.providers.length || input.providers.length > 20)
      throw new ServiceError('请保留 1 至 20 个 AI 服务商');
    const ids = new Set();
    providers = input.providers.map(p => {
      if (!p || typeof p.id !== 'string' || p.id.length > 64 || p.id.trim() !== p.id
        || !/^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$/.test(p.id) || ids.has(p.id))
        throw new ServiceError('服务商 ID 必须唯一，以小写字母开头，仅使用小写字母、数字和连字符');
      ids.add(p.id);
      const models = modelCatalog(p.models);
      if (p.apiProtocol === 'openai-responses' && models.some(m => m.maxTokens !== undefined && m.maxTokens < 16))
        throw new ServiceError('Responses 的最大输出 token 数至少为 16');
      return { id: p.id, name: required(p.name || p.id, '显示名称', 80), baseURL: apiURL(p.baseURL),
        apiProtocol: apiProtocol(p.apiProtocol), model: modelName(p.model, true),
        models, catalogConfigured: p.catalogConfigured === true };
    });
    selected = providers.find(p => p.id === providerId);
    if (!selected) throw new ServiceError('当前 AI 服务商不存在，请重新选择');
  } else if (providerId !== 'default') {
    // An individual connection used for testing or model discovery still carries its identity.
    if (typeof providerId !== 'string' || providerId.length > 64 || providerId.trim() !== providerId
      || !/^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$/.test(providerId))
      throw new ServiceError('服务商 ID 无效');
  }
  const effort = input.effort ?? 'high';
  if (!REASONING_LEVELS.includes(effort)) throw new ServiceError('请选择有效的思考等级');
  return {
    baseURL: apiURL(selected.baseURL),
    model: modelName(selected.model, !requireModel),
    apiProtocol: apiProtocol(selected.apiProtocol),
    providerId,
    ...(providers ? { providers } : {}),
    ...(!providers && input.models !== undefined ? { models: modelCatalog(input.models) } : {}),
    timeout: Math.min(600, Math.max(10, Number(input.timeout) || 120)),
    effort,
    enabled: input.enabled !== false,
    prompts: Object.fromEntries(Object.entries(DEFAULT_PROMPTS).map(([task, fallback]) => {
      const custom = input.prompts?.[task];
      return [task, typeof custom === 'string' && custom.trim() ? custom.trim().slice(0, 6000) : fallback];
    })),
  };
}
