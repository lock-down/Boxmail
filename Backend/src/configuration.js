import { createHash, randomUUID } from 'node:crypto';
import { accountInput, aiConfig, aiCredentialAccounts, ServiceError } from './validation.js';

const object = value => value && typeof value === 'object' && !Array.isArray(value);
const fail = message => { throw new ServiceError(message); };
const emailKey = account => account.email.trim().toLowerCase();
const idValid = value => typeof value === 'string' && /^[a-zA-Z0-9_-]{1,128}$/.test(value);
const referenceValid = value => typeof value === 'string' && /^configuration-[0-9a-f-]{36}$/i.test(value)
  && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value.slice(14));

function settingsInput(value) {
  if (!object(value) || !object(value.ai) || !object(value.preferences)) fail('配置文件缺少 AI 或偏好设置');
  const p = value.preferences;
  const preferences = {};
  for (const key of ['markRead', 'launchAtLogin', 'notifications', 'blockRemoteImages', 'spamFilter']) {
    if (typeof p[key] !== 'boolean') fail('配置文件中的偏好设置格式无效');
    preferences[key] = p[key];
  }
  for (const [key, min, max] of [['syncMinutes', 1, 60], ['fontSize', 12, 24]]) {
    if (!Number.isInteger(p[key]) || p[key] < min || p[key] > max) fail('配置文件中的同步间隔或字号无效');
    preferences[key] = p[key];
  }
  if (typeof p.signature !== 'string' || p.signature.length > 4000
    || typeof p.language !== 'string' || !p.language.trim() || p.language.length > 100)
    fail('配置文件中的签名或语言设置无效');
  preferences.signature = p.signature;
  preferences.language = p.language;
  return { id: 'settings', ai: aiConfig(value.ai, { requireModel: false }), preferences };
}

function configurationInput(value) {
  if (!object(value) || !Array.isArray(value.accounts) || value.accounts.length > 100)
    fail('配置文件最多支持 100 个邮箱账号');
  const ids = new Set(), emails = new Set();
  const accounts = value.accounts.map(input => {
    if (!object(input) || !idValid(input.id) || input.isDemo === true) fail('配置文件中的邮箱账号无效');
    if (typeof input.imapTLS !== 'boolean' || typeof input.smtpTLS !== 'boolean') fail('邮箱加密方式无效');
    const account = accountInput(input);
    if (ids.has(account.id) || emails.has(emailKey(account))) fail('配置文件包含重复邮箱账号');
    ids.add(account.id); emails.add(emailKey(account));
    return account;
  });
  return { accounts, settings: settingsInput(value.settings) };
}

export function exportConfiguration(repo, settings) {
  return configurationInput({ accounts: repo.list('account').filter(account => !account.isDemo),
    settings: settings ?? repo.get('settings', 'settings') });
}

function revision(repo) {
  const accounts = repo.list('account').map(account => ({ ...account, lastSync: null })).sort((a, b) => a.id.localeCompare(b.id));
  return createHash('sha256').update(JSON.stringify({ accounts, settings: repo.get('settings', 'settings') })).digest('hex');
}

export function inspectConfiguration(repo, value, requestedMapping) {
  const configuration = configurationInput(value);
  const current = repo.list('account');
  const requested = requestedMapping ?? [];
  if (requestedMapping && (!Array.isArray(requested) || requested.length !== configuration.accounts.length))
    fail('配置导入的账号映射无效，请重新选择配置文件');
  const targets = new Set();
  const accounts = configuration.accounts.map(source => {
    const matches = current.filter(account => !account.isDemo && emailKey(account) === emailKey(source));
    if (matches.length > 1) fail(`当前存在多个 ${source.email} 账号，请先在账号设置中整理后再导入`);
    const existing = matches[0];
    const mapping = requested.find(item => item?.sourceId === source.id);
    const accountId = existing?.id ?? mapping?.accountId ?? randomUUID();
    if (!idValid(accountId) || targets.has(accountId) || (!existing && current.some(account => account.id === accountId))
      || (requestedMapping && (!mapping || mapping.accountId !== accountId))) fail('配置导入的账号映射已变化，请重新选择配置文件');
    targets.add(accountId);
    return { sourceId: source.id, accountId, name: source.name, email: source.email, existing: !!existing };
  });
  return { revision: revision(repo), accounts };
}

export function importConfiguration(repo, body) {
  if (body.approved !== true) fail('导入配置需要明确确认');
  const configuration = configurationInput(body.configuration);
  if (body.revision !== revision(repo)) throw new ServiceError('账号或设置已变化，请重新选择配置文件再导入', 409);
  const plan = inspectConfiguration(repo, configuration, body.accounts);
  const references = body.credentialReferences;
  const expected = new Set([...aiCredentialAccounts(configuration.settings.ai), ...plan.accounts.map(account => `mail-${account.accountId}`)]);
  if (!object(references) || Object.keys(references).length !== expected.size
    || Object.entries(references).some(([key, value]) => !expected.has(key) || !referenceValid(value))
    || new Set(Object.values(references)).size !== expected.size) fail('凭证保存状态无效，请重新导入配置');
  return repo.transaction(() => {
    for (const entry of plan.accounts) {
      const source = configuration.accounts.find(account => account.id === entry.sourceId);
      const old = repo.get('account', entry.accountId);
      repo.put('account', { ...old, ...source, id: entry.accountId, lastSync: old?.lastSync ?? null });
    }
    const old = repo.get('settings', 'settings');
    repo.put('settings', { ...configuration.settings,
      credentialReferences: { ...old?.credentialReferences, ...references } });
    repo.event('configuration-import', `导入 ${plan.accounts.length} 个邮箱账号及 AI、签名和偏好设置`);
    return { ok: true, accounts: repo.list('account'), settings: repo.get('settings', 'settings') };
  });
}
