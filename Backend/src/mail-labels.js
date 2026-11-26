import { ServiceError } from './validation.js';

export function labelMembership(categories, message) {
  if (message.labels) return { ...message.labels };
  const category = categories.find(item => item.id !== 'unclassified' && item.name === message.category);
  return category ? { [category.id]: 'legacy' } : {};
}

export function replaceLegacyLabel(repo, message, name, source = 'rule') {
  const categories = repo.get('categoryCatalog', 'categories')?.items || [];
  const labels = labelMembership(categories, message);
  const previous = categories.find(item => item.name === message.category);
  const next = categories.find(item => item.id !== 'unclassified' && item.name === name);
  if (previous?.id !== next?.id && ['legacy', 'rule'].includes(labels[previous?.id])) delete labels[previous.id];
  if (next && !Object.hasOwn(labels, next.id) && !message.excludedLabels?.includes(next.id)) labels[next.id] = source;
  return { ...message, category: name, ...(message.labels || next ? { labels } : {}) };
}

export function addMatchedLabels(categories, message, ids) {
  const labels = labelMembership(categories, message);
  for (const id of ids) if (!message.excludedLabels?.includes(id) && !Object.hasOwn(labels, id)) labels[id] = 'model';
  return { ...message, labels };
}

export function updateMailLabels(repo, { messageIds, labelId, add }) {
  const catalog = repo.get('categoryCatalog', 'categories')?.items || [];
  if (!catalog.some(item => item.id === labelId && item.id !== 'unclassified') || typeof add !== 'boolean')
    throw new ServiceError('请选择有效标签');
  if (!Array.isArray(messageIds) || !messageIds.length || messageIds.length > 1000
    || messageIds.some(id => typeof id !== 'string')) throw new ServiceError('请选择 1 至 1000 封已加载的邮件');
  return repo.transaction(() => {
    const messages = [...new Set(messageIds)].map(id => repo.get('message', id));
    if (messages.some(message => !message)) throw new ServiceError('所选邮件已移动，请刷新后重试', 409);
    for (const message of messages) {
      const labels = labelMembership(catalog, message);
      const exclusions = new Set(message.excludedLabels);
      if (add) { labels[labelId] = 'manual'; exclusions.delete(labelId); }
      else { delete labels[labelId]; exclusions.add(labelId); }
      repo.put('message', { ...message, labels, excludedLabels: [...exclusions] });
    }
    return { ok: true };
  });
}

export function withoutLabel(message, id) {
  if (!Object.hasOwn(message.labels || {}, id) && !message.excludedLabels?.includes(id)) return message;
  const labels = { ...message.labels };
  delete labels[id];
  return { ...message, labels, excludedLabels: (message.excludedLabels || []).filter(value => value !== id) };
}
