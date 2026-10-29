import { textSlice } from './unicode.js';
import { readFile, writeFile, mkdir, copyFile, chmod, rm } from 'node:fs/promises';
import { constants } from 'node:fs';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { ServiceError } from './validation.js';
import { isPresentation } from './presentations.js';
import { processPDF } from './pdf-processing.js';
import { errorDiagnostic } from './diagnostics.js';
import { MailContentWorker } from './mail-content-worker.js';
import { attachmentContentType, attachmentMetadata } from './attachment-metadata.js';

export async function extractText(buffer, name, contentType = '', { signal, contentWorker, diagnostics, account } = {}) {
  contentType = attachmentContentType(contentType);
  signal?.throwIfAborted();
  const ext = path.extname(name).toLowerCase();
  if (['.txt', '.csv', '.md', '.json', '.log'].includes(ext))
    return textSlice(buffer.toString('utf8'), 0, 200000);
  const task = ext === '.pdf' ? 'pdf' : ['.docx', '.xlsx'].includes(ext) ? ext.slice(1)
    : isPresentation({ name, contentType }) ? 'presentation-text' : null;
  if (!task) return '';
  const parser = contentWorker || new MailContentWorker({ signal, diagnostics, account });
  try { return (await parser.run(task, buffer, { task: 'text', name, contentType, format: ext.slice(1) })).text; }
  finally { if (!contentWorker) await parser.close(); }
}
export async function saveAttachment(
  repo,
  messageId,
  name,
  buffer,
  contentType = 'application/octet-stream',
) {
  const attachment = await prepareAttachment(repo, messageId, name, buffer, contentType);
  try { return repo.put('attachment', attachment); }
  catch (error) {
    await rm(attachment.path, { force: true }).catch(() => {});
    throw error;
  }
}

// Prepare the file before a synchronous transaction publishes it with its owner.
export async function prepareAttachment(
  repo, messageId, name, buffer, contentType = 'application/octet-stream', { signal, contentWorker } = {},
) {
  signal?.throwIfAborted();
  if (buffer.length > 25 * 1024 * 1024)
    throw new ServiceError('单个附件超过 25 MB');
  const id = randomUUID();
  ({ contentType } = attachmentMetadata({ id, contentType }, { diagnostics: repo.diagnostics, phase: 'persist' }));
  const folder = path.join(repo.directory, 'attachments');
  await mkdir(folder, { recursive: true, mode: 0o700 });
  const file = path.join(
    folder,
    id +
      path
        .extname(name)
        .replace(/[^.a-zA-Z0-9]/g, '')
        .slice(0, 12),
  );
  try {
    await writeFile(file, buffer, { mode: 0o600, flag: 'wx' });
    let text = '', parseError = '';
    try { text = await extractText(buffer, name, contentType, { signal, contentWorker, diagnostics: repo.diagnostics }); }
    catch (error) {
      repo.diagnostics?.record('attachment.parse.failed', { phase: 'attachment', ...errorDiagnostic(error) });
      parseError = '文件解析未完成，原文件已保存，可下载原文件查看';
    }
    signal?.throwIfAborted();
    return {
      id, messageId, name: path.basename(name), size: buffer.length, contentType,
      path: file, text, analysis: null, parseError, date: new Date().toISOString(),
    };
  } catch (error) {
    if (error.code !== 'EEXIST') await rm(file, { force: true }).catch(() => {});
    throw error;
  }
}
export async function attachmentBytes(repo, id) {
  const a = repo.get('attachment', id);
  if (!a) throw new ServiceError('附件不存在', 404);
  return { metadata: a, buffer: await readFile(a.path) };
}

export async function removeUnusedAttachments(repo, ids) {
  // Remove records before yielding to file I/O. A concurrent draft save then
  // cannot acquire a reference to a file that is already scheduled for removal.
  const files = repo.transaction(() => {
    const candidates = new Set(ids);
    // Old sent drafts are delivery receipts. Their files belong to the Sent
    // message; stale receipt references must not prevent an approved purge.
    const receipts = repo.db.prepare(`SELECT id,json_extract(data,'$.attachmentIds') AS ids FROM records
      WHERE kind='draft' AND json_extract(data,'$.status')='sent'`).all();
    for (const receipt of receipts) {
      const previous = receipt.ids ? JSON.parse(receipt.ids) : [];
      const kept = previous.filter(id => !candidates.has(id));
      if (kept.length !== previous.length) repo.db.prepare(
        "UPDATE records SET data=json_set(data,'$.attachmentIds',json(?)) WHERE kind='draft' AND id=?")
        .run(JSON.stringify(kept), receipt.id);
    }
    const rows = repo.db.prepare(`SELECT json_extract(data,'$.attachmentIds') AS ids FROM records
      WHERE kind IN ('message','draft') UNION ALL
      SELECT json_extract(data,'$.original.attachmentIds') AS ids FROM records
      WHERE kind IN ('relocation','recovery')`).all();
    const referenced = new Set(rows.flatMap(row => row.ids ? JSON.parse(row.ids) : []));
    const unused = [];
    for (const id of candidates) {
      if (referenced.has(id)) continue;
      const attachment = repo.get('attachment', id);
      if (!attachment) continue;
      repo.remove('attachment', id);
      unused.push(attachment.path);
    }
    return unused;
  });
  await Promise.allSettled(files.map(file => rm(file, { force: true })));
}

// Copies have independent ids and files so deleting or analyzing either mail cannot affect
// the other. Commit the caller's reference changes with the new records after all files copy.
export async function copyBorrowedAttachments(repo, ids, ownerId, {
  save = attachmentIds => attachmentIds, preserveMissing = false,
} = {}) {
  const copies = new Map();
  let committed = false;
  try {
    const attachmentIds = [];
    for (const id of ids) {
      const source = repo.get('attachment', id);
      if (!source) {
        if (preserveMissing) { attachmentIds.push(id); continue; }
        throw new ServiceError('附件不存在', 404);
      }
      if (source.messageId === ownerId) { attachmentIds.push(id); continue; }
      if (!copies.has(id)) {
        const copyId = randomUUID();
        const folder = path.join(repo.directory, 'attachments');
        const file = path.join(folder, copyId + path.extname(source.name).replace(/[^.a-zA-Z0-9]/g, '').slice(0, 12));
        await mkdir(folder, { recursive: true, mode: 0o700 });
        try { await copyFile(source.path, file, constants.COPYFILE_EXCL); }
        catch (error) {
          if (error.code !== 'EEXIST') await rm(file, { force: true }).catch(() => {});
          throw error;
        }
        const copy = { ...source, id: copyId, messageId: ownerId, path: file, date: new Date().toISOString() };
        copies.set(source.id, copy);
        await chmod(file, 0o600);
      }
      attachmentIds.push(copies.get(id).id);
    }
    const result = repo.transaction(() => {
      for (const copy of copies.values()) repo.put('attachment', copy);
      return save(attachmentIds);
    });
    committed = true;
    return result;
  } finally {
    if (!committed) await Promise.allSettled([...copies.values()].map(copy => rm(copy.path, { force: true })));
  }
}

// Ownership transfers only move records already exclusive to the previous owner.
export function reassignAttachments(repo, ids, messageId, ownerId) {
  for (const id of ids) {
    const attachment = repo.get('attachment', id);
    if (!attachment || (ownerId !== undefined && attachment.messageId !== ownerId))
      continue;
    repo.put('attachment', { ...attachment, messageId });
  }
}

export async function modelAttachment(repo, id, { signal } = {}) {
  signal?.throwIfAborted();
  const { metadata, buffer } = await attachmentBytes(repo, id);
  const ext = path.extname(metadata.name).toLowerCase();
  const imageTypes = { '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.png': 'image/png', '.gif': 'image/gif', '.webp': 'image/webp' };
  const imageType = imageTypes[ext] || (Object.values(imageTypes).includes(metadata.contentType) ? metadata.contentType : null);
  if (imageType)
    return { kind: 'image', images: [{ name: metadata.name, contentType: imageType, buffer }] };
  if (isPresentation(metadata)) {
    const parser = new MailContentWorker({ signal, diagnostics: repo.diagnostics });
    try {
      const result = await parser.run('presentation', buffer, { name: metadata.name, contentType: metadata.contentType, format: 'presentation' });
      for (const image of result.images || []) image.buffer = Buffer.from(image.buffer);
      return result;
    } finally { await parser.close(); }
  }
  if (ext === '.pdf' || metadata.contentType === 'application/pdf')
    return processPDF(buffer, { name: metadata.name, signal, diagnostics: repo.diagnostics });
  if (metadata.text?.trim()) return { kind: 'text', images: [] };
  throw new ServiceError('该附件格式暂不支持模型理解，请使用 PDF、PPT、PPTX、DOCX、XLSX、文本或 JPEG、PNG、GIF、WebP 图片');
}
