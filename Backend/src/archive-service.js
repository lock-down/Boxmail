import { createHash } from 'node:crypto';
import { readFile, stat } from 'node:fs/promises';
import { MailContentWorker } from './mail-content-worker.js';
import { isArchive } from './archive-reader.js';
import { ServiceError } from './validation.js';

const fileVersions = new WeakMap();
const fileVersion = info => [info.dev, info.ino, info.size, info.mtimeNs, info.ctimeNs].join(':');

export async function openArchive(repo, id, { signal, readBytes = false } = {}) {
  const attachment = repo.get('attachment', id);
  if (!attachment || !isArchive(attachment)) throw new ServiceError('ZIP 附件不存在', 404);
  let info, buffer;
  try {
    info = await stat(attachment.path, { bigint: true });
    if (info.size > 25n * 1024n * 1024n) throw new ServiceError('ZIP 原文件超过 25 MB');
    if (!fileVersions.has(repo)) fileVersions.set(repo, new Map());
    const versions = fileVersions.get(repo), version = `${attachment.path}:${fileVersion(info)}`;
    const cached = versions.get(id);
    if (!readBytes && attachment.archive && cached?.version === version && cached.hash === attachment.archive.hash)
      return { attachment, archive: attachment.archive };
    buffer = await readFile(attachment.path, { signal });
    const after = await stat(attachment.path, { bigint: true });
    if (fileVersion(after) !== fileVersion(info)) throw new ServiceError('附件在读取期间已改变，请重新打开', 409);
    versions.set(id, { version, hash: createHash('sha256').update(buffer).digest('hex') });
  } catch (error) {
    if (error.code === 'ENOENT') throw new ServiceError('附件原文件已丢失，请重新同步或恢复附件', 404);
    throw error;
  }
  const hash = fileVersions.get(repo).get(id).hash;
  let archive = attachment.archive;
  if (archive?.hash !== hash) {
    const parser = new MailContentWorker({ signal, diagnostics: repo.diagnostics });
    try {
      archive = { ...await parser.run('archive-list', buffer, { format: 'zip' }), hash, status: 'pending', summary: null };
    } finally { await parser.close(); }
    const current = repo.get('attachment', id);
    if (!current || current.path !== attachment.path || current.messageId !== attachment.messageId)
      throw new ServiceError('附件已移动或移除，请重新打开', 409);
    if (current.archive?.hash === hash) archive = current.archive;
    else repo.put('attachment', { ...current, archive });
  }
  return { attachment: repo.get('attachment', id), archive, buffer };
}
export async function archiveEntry(repo, id, entryId, { signal } = {}) {
  const opened = await openArchive(repo, id, { signal, readBytes: true });
  if (!opened.archive.entries.some(entry => entry.id === entryId)) throw new ServiceError('包内文件不存在', 404);
  const parser = new MailContentWorker({ signal, diagnostics: repo.diagnostics });
  try {
    const file = await parser.run('archive-entry', opened.buffer, { entryId, format: 'zip' });
    return { ...file, buffer: Buffer.from(file.buffer) };
  } finally { await parser.close(); }
}
