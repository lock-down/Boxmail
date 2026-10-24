import { ServiceError } from './validation.js';
import { updateMessage } from './mail.js';

const fields = new Set(['folder', 'category', 'unread', 'starred']);

// A batch is one local transaction. Expected values make undo fail safely if
// another operation has since changed the same fields.
export function updateMessageBatch(repo, input, lockedAccounts = new Set()) {
  if (!Array.isArray(input.updates) || !input.updates.length || input.updates.length > 1000)
    throw new ServiceError('请选择 1 至 1000 封已加载的邮件');
  const ids = new Set();
  const updates = input.updates.map(update => {
    if (!update || typeof update.id !== 'string' || !update.id || ids.has(update.id))
      throw new ServiceError('邮件选择无效或重复，请重新选择');
    ids.add(update.id);
    const message = repo.get('message', update.id);
    if (!message) throw new ServiceError('所选邮件已移动或不存在，请刷新列表后重试', 409);
    if (!update.changes || typeof update.changes !== 'object' || Array.isArray(update.changes)
      || !Object.keys(update.changes).length || Object.keys(update.changes).some(key => !fields.has(key)))
      throw new ServiceError('邮件操作格式不正确');
    if (lockedAccounts.has(message.accountId)
      && ['folder', 'unread', 'starred'].some(key => Object.hasOwn(update.changes, key)))
      throw new ServiceError('所选账户正在同步或清空邮件，请完成后重试', 409);
    if (update.expected !== undefined) {
      if (!update.expected || typeof update.expected !== 'object' || Array.isArray(update.expected)
        || Object.keys(update.expected).some(key => !fields.has(key)))
        throw new ServiceError('撤销条件格式不正确');
      if (Object.entries(update.expected).some(([key, value]) => message[key] !== value))
        throw new ServiceError('邮件状态已被其他操作更改，未覆盖现有状态，请刷新后检查', 409);
    }
    return { message, changes: { ...update.changes } };
  });
  return repo.transaction(() => {
    const undo = [];
    for (const { message, changes } of updates) {
      const effective = Object.fromEntries(Object.entries(changes).filter(([key, value]) => message[key] !== value));
      if (!Object.keys(effective).length) continue;
      const updated = updateMessage(repo, message.id, effective);
      const changed = Object.keys(changes).filter(key => updated[key] !== message[key]);
      if (changed.length) undo.push({ id: message.id,
        changes: Object.fromEntries(changed.map(key => [key, message[key]])),
        expected: Object.fromEntries(changed.map(key => [key, updated[key]])) });
    }
    return { changedCount: undo.length, undo };
  });
}
