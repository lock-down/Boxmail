import { setImmediate as yieldToRequests } from 'node:timers/promises';
import { removeUnusedAttachments } from './attachments.js';

export const RECOVERY_TTL_MS = 30 * 24 * 60 * 60 * 1000;
export const MAX_RETAINED_MAIL = 2000;

export async function pruneMailRecovery(repo, accountId, { signal, now = Date.now() } = {}) {
  // Give legacy records a migration grace period without decoding their bodies.
  repo.db.prepare(`UPDATE records SET data=json_set(data,'$.createdAt',?)
    WHERE kind IN ('recovery','relocation') AND json_extract(data,'$.accountId')=?
    AND json_extract(data,'$.createdAt') IS NULL`).run(new Date(now).toISOString(), accountId);
  const rows = repo.db.prepare(`SELECT kind,id,json_extract(data,'$.createdAt') AS createdAt,
    json_extract(data,'$.original.attachmentIds') AS attachments FROM records
    WHERE kind IN ('recovery','relocation') AND json_extract(data,'$.accountId')=?
    ORDER BY json_extract(data,'$.createdAt') DESC,id`).all(accountId);
  const stale = rows.filter((row, index) => index >= MAX_RETAINED_MAIL
    || !Number.isFinite(Date.parse(row.createdAt)) || Date.parse(row.createdAt) < now - RECOVERY_TTL_MS);
  for (let offset = 0; offset < stale.length; offset += 100) {
    signal?.throwIfAborted();
    const batch = stale.slice(offset, offset + 100);
    repo.transaction(() => { for (const row of batch) repo.remove(row.kind, row.id); });
    await removeUnusedAttachments(repo, batch.flatMap(row => row.attachments ? JSON.parse(row.attachments) : []));
    await yieldToRequests(undefined, { signal });
  }
  if (stale.length) repo.event('sync', `已清理 ${stale.length} 条超过保留期限或数量上限的邮件恢复记录及未引用附件。`);
}
