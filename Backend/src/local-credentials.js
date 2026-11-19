import { readFileSync, lstatSync } from 'node:fs';
import path from 'node:path';
import { ServiceError } from './validation.js';

// Same single-line dotenv contract as EnvCredentialStore. Resolve bindings at
// execution time, so imported configurations never inherit another endpoint's key.
export function parseCredentials(text) {
  const values = new Map();
  for (const [index, line] of text.replace(/^\uFEFF/, '').replaceAll('\r\n', '\n').split('\n').entries()) {
    const source = line.trim().replace(/^export\s+/, '');
    if (!source || source.startsWith('#')) continue;
    const match = /^([A-Za-z_][A-Za-z0-9_.-]*)\s*=\s*(.*)$/.exec(source);
    const fail = () => { throw new ServiceError(`.env 第 ${index + 1} 行格式无效`); };
    if (!match) fail();
    let value = match[2];
    if (value.startsWith('"') || value.startsWith("'")) {
      const quote = value[0];
      let escaped = false, end = -1;
      for (let i = 1; i < value.length; i++) {
        if (escaped) { escaped = false; continue; }
        if (quote === '"' && value[i] === '\\') { escaped = true; continue; }
        if (value[i] === quote) { end = i; break; }
      }
      if (end < 0 || !/^(?:\s*#.*|\s*)$/.test(value.slice(end + 1))) fail();
      try { value = quote === '"' ? JSON.parse(value.slice(0, end + 1)) : value.slice(1, end); }
      catch { fail(); }
    } else value = value.split('#')[0].trim();
    values.set(match[1], value);
  }
  return values;
}

export class LocalCredentials {
  constructor(repo, file = process.env.BOXMAIL_ENV_FILE || path.join(repo.directory, '.env')) {
    this.repo = repo; this.file = file;
    if (!path.isAbsolute(file) || file.includes('\0')) throw new ServiceError('BOXMAIL_ENV_FILE 必须是绝对路径');
  }
  read(logical) {
    const reference = this.repo.get('settings', 'settings')?.credentialReferences?.[logical] || logical;
    let key;
    if (/^configuration-[0-9a-f-]{36}$/i.test(reference)) key = `BOXMAIL_CONFIGURATION_${reference.slice(14)}`;
    else if (reference === 'ai-key') key = 'BOXMAIL_AI_KEY';
    else if (reference.startsWith('mail-')) key = `BOXMAIL_MAIL_${reference.slice(5)}_PASSWORD`;
    else if (reference.startsWith('ai-provider-')) key = `BOXMAIL_AI_PROVIDER_${reference.slice(12)}_KEY`;
    else throw new ServiceError('凭证名称无效');
    try {
      if (!lstatSync(this.file).isFile()) throw new ServiceError('凭证文件必须是普通文件');
      return parseCredentials(readFileSync(this.file, 'utf8')).get(key) || '';
    } catch (error) {
      if (error.code === 'ENOENT') return '';
      if (error instanceof ServiceError) throw error;
      throw new ServiceError('无法读取本机凭证文件，请检查文件权限');
    }
  }
  mail(accountId) {
    const password = this.read(`mail-${accountId}`);
    if (!password) throw new ServiceError('本机 .env 未配置此邮箱授权码，请在设置中填写');
    return password;
  }
  ai() {
    const config = this.repo.get('settings', 'settings').ai;
    return { config, apiKey: this.read(config.providerId === 'default' ? 'ai-key' : `ai-provider-${config.providerId}`) };
  }
}
