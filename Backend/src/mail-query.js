import { randomUUID, createHash } from 'node:crypto';
import { parseSearch } from './search-query.js';
import { ServiceError } from './validation.js';

export const ruleRevision = (query, actions) => createHash('sha256').update(JSON.stringify([query, actions])).digest('hex');

export function renameQueryCategory(query, previous, name) {
  let changed = false;
  if (query.category === previous) { query.category = name; changed = true; }
  const parsed = parseSearch(query.query);
  for (const condition of parsed.conditions) if (condition.field === 'category' && condition.value === previous) {
    condition.value = name; changed = true;
  }
  if (changed && parsed.conditions.some(item => item.field === 'category')) query.query = [
    ...parsed.terms.map(value => JSON.stringify(value)),
    ...parsed.conditions.map(({ field, value }) => `${field}:${JSON.stringify(value)}`),
  ].join(' ');
  return changed;
}

// A saved query describes data scope; grouping, selection and scroll are view state.
export function mailQuery(input = {}) {
  const query = {
    accountId: input.accountId || null,
    folder: input.folder || 'inbox',
    query: input.query ?? input.q ?? '',
    filter: input.filter || '全部',
    category: input.category || null,
    ...(input.labelId ? { labelId: input.labelId } : {}),
  };
  if (query.accountId !== null && typeof query.accountId !== 'string'
    || !['inbox', 'sent', 'archive', 'trash', 'spam', 'starred', 'summary', 'drafts', 'replies', 'analysis'].includes(query.folder)
    || !['全部', '未读', '有附件', 'AI 已总结'].includes(query.filter)
    || query.category !== null && typeof query.category !== 'string'
    || query.labelId !== undefined && typeof query.labelId !== 'string') throw new ServiceError('查询范围无效');
  parseSearch(query.query);
  return query;
}

export class SavedSearches {
  constructor(repo) { this.repo = repo; }
  list() { return this.repo.list('savedSearch'); }
  save(input, id = randomUUID()) {
    const name = typeof input.name === 'string' ? input.name.trim() : '';
    if (!name) throw new ServiceError('请填写视图名称');
    const query = mailQuery(input.query);
    if (query.accountId && !this.repo.get('account', query.accountId)) throw new ServiceError('查询账户不存在');
    return this.repo.put('savedSearch', { id, name, query });
  }
  remove(id) { this.repo.remove('savedSearch', id); return { ok: true }; }
}
