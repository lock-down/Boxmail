import { ServiceError } from './validation.js';

const fields = new Set(['from', 'to', 'cc', 'subject', 'after', 'before', 'is', 'has', 'account', 'folder', 'category']);
export const folderAliases = { 收件箱: 'inbox', 已发送: 'sent', 已归档: 'archive', 已删除: 'trash', 垃圾邮件: 'spam', 草稿箱: 'drafts' };
export function parseSearch(query = '') {
  if (typeof query !== 'string' || query.length > 4000) throw new ServiceError('搜索内容最多 4000 个字符');
  const tokens = [];
  let token = '', quoted = false, escaped = false, literal = false;
  for (const char of query.trim()) {
    if (escaped) { token += char; escaped = false; }
    else if (char === '\\' && quoted) escaped = true;
    else if (char === '"') { if (!quoted && !token) literal = true; quoted = !quoted; }
    else if (/\s/u.test(char) && !quoted) { if (token) tokens.push({ token, literal }); token = ''; literal = false; }
    else token += char;
  }
  if (quoted || escaped) throw new ServiceError('搜索引号未闭合，请使用成对的英文双引号');
  if (token) tokens.push({ token, literal });
  if (tokens.length > 40) throw new ServiceError('搜索条件过多，请减少到 40 项以内');
  const result = { terms: [], conditions: [] };
  for (const { token, literal } of tokens) {
    const match = literal || /^(https?|mailto):/i.test(token) ? null : /^([a-z]+):(.*)$/i.exec(token);
    if (!match) { result.terms.push(token); continue; }
    const field = match[1].toLowerCase(), value = match[2].trim();
    if (!fields.has(field)) throw new ServiceError(`不支持搜索条件“${field}:”，可用 from、to、after、before、is、has、account、folder、category`);
    if (!value) throw new ServiceError(`搜索条件 ${field}: 缺少内容`);
    if (['after', 'before'].includes(field) && (!/^\d{4}-\d{2}-\d{2}$/.test(value)
      || !Number.isFinite(Date.parse(value)) || new Date(value).toISOString().slice(0, 10) !== value))
      throw new ServiceError(`${field}: 日期无效，请使用 YYYY-MM-DD`);
    if (field === 'is' && !['read', 'unread', 'starred'].includes(value.toLowerCase()))
      throw new ServiceError('is: 支持 unread、read 或 starred');
    if (field === 'has' && value.toLowerCase() !== 'attachment') throw new ServiceError('has: 目前支持 attachment');
    const resolved = field === 'folder' ? folderAliases[value] || value.toLowerCase() : value;
    if (field === 'folder' && !['inbox', 'sent', 'archive', 'trash', 'drafts', 'spam'].includes(resolved))
      throw new ServiceError('folder: 请选择 inbox、sent、archive、trash、drafts 或 spam');
    result.conditions.push({ field, value: resolved });
  }
  const after = result.conditions.find(item => item.field === 'after')?.value;
  const before = result.conditions.find(item => item.field === 'before')?.value;
  if (after && before && after >= before) throw new ServiceError('起始日期必须早于截止日期（before 不包含当天）');
  return result;
}

export function searchWhere(parsed, { accountId, folder, filter, accounts = [] } = {}) {
  const clauses = ["m.kind='message'"], params = [];
  const add = (sql, value) => { clauses.push(sql); if (value !== undefined) params.push(value); };
  if (accountId && !parsed.conditions.some(item => item.field === 'account')) add("json_extract(m.data,'$.accountId')=?", accountId);
  if (!parsed.terms.length && !parsed.conditions.length) {
    if (folder === 'starred') add("json_extract(m.data,'$.starred')=1 AND json_extract(m.data,'$.folder')!='trash'");
    else if (folder === 'summary') add("json_type(m.data,'$.summary')='object' AND json_extract(m.data,'$.folder')!='trash'");
    else if (folder) add("json_extract(m.data,'$.folder')=?", ['replies', 'analysis'].includes(folder) ? 'inbox' : folder);
  }
  for (const { field, value } of parsed.conditions) {
    if (field === 'account') {
      const candidates = accounts.filter(account => [account.id, account.email, account.name]
        .some(item => item?.toLocaleLowerCase() === value.toLocaleLowerCase()));
      if (candidates.length !== 1) throw new ServiceError(candidates.length ? '账户名称有重名，请使用完整邮箱地址' : `找不到账户“${value}”`);
      add("json_extract(m.data,'$.accountId')=?", candidates[0].id);
    } else if (['from', 'to', 'cc', 'subject', 'category'].includes(field)) {
      const columns = field === 'from' ? ['sender', 'senderEmail'] : field === 'to' ? ['to', 'cc', 'bcc'] : [field];
      const text = columns.map(column => `coalesce(json_extract(m.data,'$.${column}'),'')`).join("||char(10)||");
      add(`instr(lower(${text}),lower(?))>0`, value);
    } else if (field === 'folder') add("json_extract(m.data,'$.folder')=?", value);
    else if (field === 'after') add("date(json_extract(m.data,'$.date'),'localtime')>=?", value);
    else if (field === 'before') add("date(json_extract(m.data,'$.date'),'localtime')<?", value);
    else if (field === 'has') add("json_array_length(json_extract(m.data,'$.attachmentIds'))>0");
    else if (field === 'is') add(value.toLowerCase() === 'starred' ? "json_extract(m.data,'$.starred')=1"
      : `json_extract(m.data,'$.unread')=${value.toLowerCase() === 'unread' ? 1 : 0}`);
  }
  if (filter === '未读') add("json_extract(m.data,'$.unread')=1");
  if (filter === '有附件') add("json_array_length(json_extract(m.data,'$.attachmentIds'))>0");
  if (filter === 'AI 已总结') add("json_type(m.data,'$.summary')='object'");
  return { clauses, params };
}
