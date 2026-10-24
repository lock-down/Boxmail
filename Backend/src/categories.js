import { randomUUID } from 'node:crypto';
import { ServiceError } from './validation.js';

export const DEFAULT_CATEGORIES = ['工作项目', '订阅资讯', '账单票据', '社交通知', '个人往来', '未分类'];
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
export function editCategory(repo, id, input = {}, remove = false) {
  const categories = categoryCatalog(repo);
  if (remove && !id) throw new ServiceError('请选择要删除的分类');
  const previous = id ? categories.find(item => item.id === id) : null;
  if (id && !previous) throw new ServiceError('分类不存在，请刷新后重试', 404);
  if (previous?.id === 'unclassified') throw new ServiceError('未分类用于接收未整理邮件，不能修改或删除');
  const name = remove ? '未分类' : String(input.name ?? previous?.name ?? '').normalize('NFKC').trim();
  const description = String(input.description ?? previous?.description ?? '').trim();
  if (!name || [...name].length > 32 || /[\r\n\u0000-\u001f]/u.test(name))
    throw new ServiceError('分类名称需为 1 至 32 个字符，不能包含换行');
  if (description.length > 500) throw new ServiceError('分类说明最多 500 个字符');
  if (!remove && categories.some(item => item.id !== id && item.name.toLocaleLowerCase() === name.toLocaleLowerCase()))
    throw new ServiceError('已有同名分类');
  if (!id && categories.length >= 100) throw new ServiceError('最多保存 100 个分类，请先整理已有分类');
  return repo.transaction(() => {
    const item = { id: previous?.id || randomUUID(), name, description };
    const items = remove ? categories.filter(item => item.id !== id)
      : previous ? categories.map(value => value.id === id ? item : value) : [...categories, item];
    repo.put('categoryCatalog', { id: 'categories', items });
    if (previous && previous.name !== name) {
      for (const message of repo.list('message').filter(m => m.category === previous.name))
        repo.put('message', { ...message, category: name });
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
    repo.event('categories', remove ? `已删除分类“${previous.name}”，相关邮件归为未分类` : `已保存分类“${name}”`);
    return { categories: items };
  });
}
