import { ServiceError } from './validation.js';
import { FollowUps } from './follow-ups.js';

// Overview membership is independent of the saved summary and its todos.
export function setSummaryVisibility(repo, input) {
  if (typeof input.accountId !== 'string' || !repo.get('account', input.accountId))
    throw new ServiceError('请选择邮箱账户');
  if (typeof input.hidden !== 'boolean' || (input.all !== undefined && typeof input.all !== 'boolean'))
    throw new ServiceError('摘要列表操作格式不正确');
  if (input.all === true && input.messageIds !== undefined)
    throw new ServiceError('请选择单项或全部摘要');
  let messages;
  if (input.all === true) {
    messages = repo.list('message', { accountId: input.accountId })
      .filter(message => message.summary && message.folder !== 'trash');
  } else {
    if (!Array.isArray(input.messageIds) || !input.messageIds.length || input.messageIds.length > 10000
      || input.messageIds.some(id => typeof id !== 'string' || !id))
      throw new ServiceError('请选择需要操作的摘要');
    messages = [...new Set(input.messageIds)].map(id => repo.get('message', id));
    if (messages.some(message => !message || message.accountId !== input.accountId || !message.summary))
      throw new ServiceError('摘要已变更或不属于当前账户，请刷新后重试', 409);
  }
  const changed = messages.filter(message => (message.summaryHidden === true) !== input.hidden);
  const ids = new Set(changed.map(message => message.id));
  const followUps = new FollowUps(repo);
  repo.transaction(() => {
    for (const message of changed) repo.put('message', { ...message, summaryHidden: input.hidden });
    for (const item of repo.list('followUp', { accountId: input.accountId }))
      if (ids.has(item.messageId) && item.collected === false && item.snoozedUntil) followUps.updateSnooze(item);
    // Pending folder reconciliation carries the membership along with the original mail.
    for (const kind of ['relocation', 'recovery']) {
      for (const record of repo.list(kind)) {
        if (record.original?.accountId === input.accountId && ids.has(record.original.id))
          repo.put(kind, { ...record, original: { ...record.original, summaryHidden: input.hidden } });
      }
    }
  });
  return { messageIds: [...ids] };
}
