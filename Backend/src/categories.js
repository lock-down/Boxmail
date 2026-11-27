import { randomUUID } from 'node:crypto';
import { withoutLabel } from './mail-labels.js';
import { ServiceError } from './validation.js';
import { renameQueryCategory, ruleRevision } from './mail-query.js';

export const DEFAULT_CATEGORIES = ['工作项目', '订阅资讯', '账单票据', '社交通知', '个人往来', '未分类'];
export const isCategoryColor = value => typeof value === 'string' && /^#[0-9a-f]{6}$/i.test(value);
export function categoryCatalog(repo) {
  let catalog = repo.get('categoryCatalog', 'categories');
  if (!catalog) {
    const saved = repo.db.prepare(`SELECT json_extract(data,'$.category') AS name FROM records
      WHERE kind='message' AND json_type(data,'$.category')='text' ORDER BY id`).all();
    const names = [...new Set([...DEFAULT_CATEGORIES, ...saved.map(row => row.name).filter(Boolean)])];
    catalog = { id: 'categories', items: names.map(name => ({ id: name === '未分类' ? 'unclassified' : randomUUID(), name, description: '' })) };
    repo.put('categoryCatalog', catalog);
  }
  return catalog.items;
}
export function organizationLabelMode(repo, input, { allowEmpty = false } = {}) {
  const { mode, labelIds } = input ?? {};
  const available = new Set(categoryCatalog(repo).filter(label => label.id !== 'unclassified').map(label => label.id));
  if (!['automatic', 'existing'].includes(mode) || !Array.isArray(labelIds)
    || (mode === 'existing' ? (!allowEmpty && !labelIds.length) || labelIds.some(id => !available.has(id)) : labelIds.length > 0))
    throw new ServiceError('请核对并确认本邮箱的标签方式');
  return { mode, labelIds: [...new Set(labelIds)].sort() };
}

export function organizationCategory(repo, suggestion, supplied) {
  const categories = categoryCatalog(repo);
  if (typeof suggestion?.id === 'string') {
    return supplied.some(item => item.id === suggestion.id)
      ? categories.find(item => item.id === suggestion.id && item.id !== 'unclassified') : undefined;
  }
  if (typeof suggestion?.name !== 'string') return;
  const name = suggestion.name.normalize('NFKC').trim();
  if (!name || [...name].length > 32 || /[\r\n\u0000-\u001f]/u.test(name)) return;
  const existing = categories.find(item => item.name.normalize('NFKC').toLocaleLowerCase() === name.toLocaleLowerCase());
  if (existing) return existing.id === 'unclassified' ? undefined : existing;
  if (categories.length >= 100) return;
  const item = { id: randomUUID(), name, description: '', origin: 'mailOrganization' };
  repo.put('categoryCatalog', { id: 'categories', items: [...categories, item] });
  return item;
}

export function editCategory(repo, id, input = {}, remove = false) {
  const categories = categoryCatalog(repo);
  if (remove && !id) throw new ServiceError('请选择要删除的分类');
  const previous = id ? categories.find(item => item.id === id) : null;
  if (id && !previous) throw new ServiceError('分类不存在，请刷新后重试', 404);
  if (previous?.id === 'unclassified') throw new ServiceError('未分类用于接收未整理邮件，不能修改或删除');
  const name = remove ? '未分类' : String(input.name ?? previous?.name ?? '').normalize('NFKC').trim();
  const description = String(input.description ?? previous?.description ?? '').trim();
  const match = input.match === undefined ? previous?.match || '' : input.match;
  if (typeof match !== 'string' || match.length > 500) throw new ServiceError('标签条件最多 500 个字符');
  const condition = match.trim();
  const color = input.color === undefined ? previous?.color : input.color;
  if (!name || [...name].length > 32 || /[\r\n\u0000-\u001f]/u.test(name))
    throw new ServiceError('分类名称需为 1 至 32 个字符，不能包含换行');
  if (description.length > 500) throw new ServiceError('分类说明最多 500 个字符');
  if (color != null && !isCategoryColor(color)) throw new ServiceError('分类颜色需要使用六位十六进制色值');
  if (!remove && categories.some(item => item.id !== id && item.name.toLocaleLowerCase() === name.toLocaleLowerCase()))
    throw new ServiceError('已有同名分类');
  if (!id && categories.length >= 100) throw new ServiceError('最多保存 100 个分类，请先整理已有分类');
  return repo.transaction(() => {
    const item = { id: previous?.id || randomUUID(), name, description, ...(previous?.origin ? { origin: previous.origin } : {}), ...(condition ? { match: condition,
      matchRevision: condition === previous?.match ? previous.matchRevision || randomUUID() : randomUUID() } : {}), ...(color ? { color: color.toUpperCase() } : {}) };
    const items = remove ? categories.filter(item => item.id !== id)
      : previous ? categories.map(value => value.id === id ? item : value) : [...categories, item];
    repo.put('categoryCatalog', { id: 'categories', items });
    if (previous && previous.name !== name) {
      for (const view of repo.list('savedSearch')) if (renameQueryCategory(view.query, previous.name, name)) repo.put('savedSearch', view);
      for (const rule of repo.list('mailRule')) {
        let changed = renameQueryCategory(rule.query, previous.name, name);
        if (rule.actions.category === previous.name) { rule.actions.category = name; changed = true; }
        if (changed) repo.put('mailRule', { ...rule, revision: ruleRevision(rule.query, rule.actions) });
      }
      repo.db.prepare("UPDATE records SET data=json_set(data,'$.category',?) WHERE kind='message' AND json_extract(data,'$.category')=?").run(name, previous.name);
      repo.invalidateMessagePreviews();
      repo.searchIndex.schedule();
      for (const kind of ['relocation', 'recovery'])
        for (const record of repo.list(kind).filter(record => record.original?.category === previous.name))
          repo.put(kind, { ...record, original: { ...record.original, category: name } });
      for (const job of repo.list('job').filter(job => job.task === 'classify')) {
        for (const values of [job.result?.items, job.result?.previous])
          for (const value of values || []) {
            if (value.category === previous.name) value.category = name;
          }
        if (job.categories) job.categories = remove ? job.categories.filter(value => value.id !== id && value.name !== previous.name)
          : job.categories.map(value => value.id === id || value.name === previous.name ? { ...value, name, description } : value);
        repo.put('job', job);
      }
    }
    if (remove) {
      const records = repo.db.prepare(`SELECT data FROM records WHERE kind='message' AND (
        EXISTS (SELECT 1 FROM json_each(data,'$.labels') WHERE key=?)
        OR EXISTS (SELECT 1 FROM json_each(data,'$.excludedLabels') WHERE value=?))`).all(id, id);
      for (const row of records) repo.put('message', withoutLabel(JSON.parse(row.data), id));
      for (const kind of ['relocation', 'recovery']) for (const record of repo.list(kind)) {
        const original = withoutLabel(record.original, id);
        if (original !== record.original) repo.put(kind, { ...record, original });
      }
      for (const policy of repo.list('mailOrganizationPolicy')) if (Object.hasOwn(policy.labelRules || {}, id)) {
        const labelRules = { ...policy.labelRules };
        delete labelRules[id];
        repo.put('mailOrganizationPolicy', { ...policy, labelRules });
      }
    }
    repo.messageRevision++;
    repo.event('categories', remove ? `已删除分类“${previous.name}”，相关邮件归为未分类` : `已保存分类“${name}”`);
    return { categories: items };
  });
}
