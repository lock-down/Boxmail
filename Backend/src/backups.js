import { DatabaseSync } from 'node:sqlite';
import { createReadStream, createWriteStream } from 'node:fs';
import { mkdir, mkdtemp, lstat, readFile, writeFile, chmod, rename, rm } from 'node:fs/promises';
import { pipeline } from 'node:stream/promises';
import { Readable, Writable } from 'node:stream';
import { createHash, randomUUID } from 'node:crypto';
import os from 'node:os';
import path from 'node:path';
import JSZip from 'jszip';
import { ServiceError } from './validation.js';
import { validateBackupRecords } from './backup-validation.js';

const MB = 1024 * 1024;
const MAX_ARCHIVE = 512 * MB, MAX_DATABASE = 256 * MB, MAX_TOTAL = 2048 * MB;
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const filenameFor = id => `attachments/${hash(id)}.bin`;
async function fileStat(file) {
  const info = await lstat(file).catch(() => { throw new ServiceError('文件不存在或磁盘不可用'); });
  if (!info.isFile() || info.isSymbolicLink()) throw new ServiceError('请选择普通文件，不支持符号链接');
  return info;
}
async function fileInfo(file) {
  const info = await fileStat(file);
  const digest = createHash('sha256');
  for await (const chunk of createReadStream(file)) digest.update(chunk);
  return { size: info.size, sha256: digest.digest('hex') };
}
function absoluteFile(value) {
  if (typeof value !== 'string' || !path.isAbsolute(value) || value.includes('\0'))
    throw new ServiceError('请选择本机备份文件的完整路径');
  return path.resolve(value);
}
async function entryBytes(entry, limit) {
  if (!entry) throw new ServiceError('备份文件缺失');
  let size = 0;
  const chunks = [];
  await pipeline(entry.nodeStream(), new Writable({ write(chunk, encoding, callback) {
    size += chunk.length;
    if (size > limit) return callback(new ServiceError('备份文件内容超过支持的大小'));
    chunks.push(chunk); callback();
  } }));
  return Buffer.concat(chunks);
}

export async function createBackup(repo, destination) {
  destination = absoluteFile(destination);
  const relative = path.relative(repo.directory, destination);
  if (!destination.toLowerCase().endsWith('.zip') || relative === 'boxmail.sqlite'
    || relative === 'attachments' || relative.startsWith(`attachments${path.sep}`))
    throw new ServiceError('请将备份保存为 ZIP，且不要放入附件目录');
  const existing = await lstat(destination).catch(() => null);
  if (existing && (!existing.isFile() || existing.isSymbolicLink()))
    throw new ServiceError('备份目标不是普通文件');
  const staging = await mkdtemp(path.join(os.tmpdir(), 'boxmail-backup-'));
  const partial = `${destination}.partial-${randomUUID()}`;
  const streams = [];
  try {
    const database = path.join(staging, 'boxmail.sqlite');
    repo.db.exec(`VACUUM INTO '${database.replaceAll("'", "''")}'`);
    await chmod(database, 0o600);
    const info = await fileInfo(database);
    if (info.size > MAX_DATABASE) throw new ServiceError('数据库超过 256 MB，请先在退出应用后备份完整数据目录');
    const manifest = { format: 'boxmail-backup', version: 1, schemaVersion: 2,
      createdAt: new Date().toISOString(), credentialsIncluded: false,
      counts: Object.fromEntries(['account', 'message', 'draft', 'attachment', 'job', 'mutation']
        .map(kind => [kind, repo.list(kind).length])),
      files: [{ path: 'boxmail.sqlite', ...info }],
    };
    const zip = new JSZip();
    const addFile = (name, file) => {
      const stream = Readable.from((async function* () { yield* createReadStream(file); })());
      streams.push(stream);
      zip.file(name, stream);
    };
    addFile('boxmail.sqlite', database);
    let total = info.size;
    for (const attachment of repo.list('attachment')) {
      const attachmentInfo = await fileInfo(attachment.path).catch(() => {
        throw new ServiceError(`附件“${attachment.name || attachment.id}”缺失或不可读取，未创建不完整备份`);
      });
      if (attachmentInfo.size > 50 * MB) throw new ServiceError('单个附件超过备份支持的 50 MB');
      total += attachmentInfo.size;
      if (total > MAX_TOTAL) throw new ServiceError('备份内容超过 2 GB，请在退出应用后备份完整数据目录');
      const entry = { path: filenameFor(attachment.id), attachmentId: attachment.id, ...attachmentInfo };
      manifest.files.push(entry);
      addFile(entry.path, attachment.path);
    }
    zip.file('manifest.json', JSON.stringify(manifest, null, 2));
    await pipeline(zip.generateNodeStream({ streamFiles: true, compression: 'DEFLATE',
      compressionOptions: { level: 6 } }), createWriteStream(partial, { flags: 'wx', mode: 0o600 }));
    const archive = await fileInfo(partial);
    if (archive.size > MAX_ARCHIVE) throw new ServiceError('压缩备份超过 512 MB，请在退出应用后备份完整数据目录');
    // Read back every checksum before exposing the completed backup.
    await withValidatedBackup(partial, async () => {});
    await rename(partial, destination);
    return { path: destination, ...archive, ...summary(manifest) };
  } finally {
    for (const stream of streams) stream.destroy();
    await rm(partial, { force: true }).catch(() => {});
    await rm(staging, { recursive: true, force: true });
  }
}

function summary(manifest) {
  return { createdAt: manifest.createdAt, counts: manifest.counts, credentialsIncluded: false,
    totalBytes: manifest.files.reduce((sum, entry) => sum + entry.size, 0) };
}

async function withValidatedBackup(source, action, expectedSHA256) {
  source = absoluteFile(source);
  if ((await fileStat(source)).size > MAX_ARCHIVE) throw new ServiceError('备份压缩文件超过 512 MB');
  const staging = await mkdtemp(path.join(os.tmpdir(), 'boxmail-restore-check-'));
  try {
    let zip;
    const archiveBytes = await readFile(source);
    if (archiveBytes.length > MAX_ARCHIVE) throw new ServiceError('备份压缩文件超过 512 MB');
    const archiveSHA256 = hash(archiveBytes);
    if (expectedSHA256 && archiveSHA256 !== expectedSHA256)
      throw new ServiceError('备份文件在检查后已改变，请重新选择并确认', 409);
    try { zip = await JSZip.loadAsync(archiveBytes); }
    catch { throw new ServiceError('无法读取备份 ZIP，文件可能损坏'); }
    const entries = Object.values(zip.files);
    if (entries.length > 100_010) throw new ServiceError('备份文件数量超过支持范围');
    for (const entry of entries) {
      if (entry.unsafeOriginalName && entry.unsafeOriginalName !== entry.name
        || entry.name.startsWith('/') || entry.name.includes('\\')
        || entry.name.split('/').some(part => part === '..' || part === '.'))
        throw new ServiceError('备份包含不安全的文件路径');
    }
    let manifest;
    try { manifest = JSON.parse((await entryBytes(zip.file('manifest.json'), 4 * MB)).toString()); }
    catch { throw new ServiceError('备份清单无效或缺失'); }
    if (manifest.format !== 'boxmail-backup' || manifest.version !== 1 || manifest.schemaVersion > 2
      || !Array.isArray(manifest.files) || !manifest.files.length || !manifest.counts)
      throw new ServiceError('备份格式或版本不受支持，请使用兼容的 Boxmail');
    const names = new Set(), ids = new Set();
    let total = 0;
    for (const entry of manifest.files) {
      if (!entry || typeof entry.path !== 'string' || names.has(entry.path)
        || !Number.isSafeInteger(entry.size) || entry.size < 0 || !/^[a-f0-9]{64}$/.test(entry.sha256 || '')
        || !(entry.path === 'boxmail.sqlite' || typeof entry.attachmentId === 'string'
          && entry.path === filenameFor(entry.attachmentId) && !ids.has(entry.attachmentId)))
        throw new ServiceError('备份文件清单无效');
      if (entry.attachmentId) ids.add(entry.attachmentId);
      names.add(entry.path); total += entry.size;
      if (total > MAX_TOTAL || entry.size > (entry.path === 'boxmail.sqlite' ? MAX_DATABASE : 50 * MB))
        throw new ServiceError('备份解压内容超过支持的大小');
      const bytes = await entryBytes(zip.file(entry.path), entry.size);
      if (bytes.length !== entry.size || hash(bytes) !== entry.sha256)
        throw new ServiceError('备份校验失败，当前数据未更改');
      const target = path.join(staging, entry.path);
      await mkdir(path.dirname(target), { recursive: true, mode: 0o700 });
      await writeFile(target, bytes, { mode: 0o600, flag: 'wx' });
    }
    if (!names.has('boxmail.sqlite') || entries.some(entry => !entry.dir && entry.name !== 'manifest.json' && !names.has(entry.name)))
      throw new ServiceError('备份含有未列入清单的文件');
    let db;
    try {
      db = new DatabaseSync(path.join(staging, 'boxmail.sqlite'), { readOnly: true });
      if (db.prepare('PRAGMA integrity_check').get().integrity_check !== 'ok'
        || db.prepare('PRAGMA user_version').get().user_version > 2) throw new Error('Invalid database');
      const records = db.prepare('SELECT kind,id,data FROM records').all();
      const events = db.prepare('SELECT id,time,type,detail FROM events').all();
      for (const row of records) {
        const value = JSON.parse(row.data);
        if (!value || typeof value !== 'object' || value.id !== row.id) throw new Error('Invalid record');
      }
      validateBackupRecords(records);
      const attachments = records.filter(row => row.kind === 'attachment');
      if (attachments.length !== ids.size || attachments.some(row => !ids.has(row.id))) throw new Error('Attachment mismatch');
      const counts = Object.fromEntries(Object.keys(manifest.counts).map(kind => [kind, records.filter(row => row.kind === kind).length]));
      if (Object.entries(counts).some(([kind, count]) => count !== manifest.counts[kind])) throw new Error('Count mismatch');
      db.close(); db = null;
      return await action({ manifest, records, events, staging, archiveSHA256 });
    } catch (error) {
      if (error instanceof ServiceError) throw error;
      throw new ServiceError('备份数据库或附件关联无效，当前数据未更改');
    } finally { db?.close(); }
  } finally { await rm(staging, { recursive: true, force: true }); }
}

export async function inspectBackup(source) {
  return withValidatedBackup(source, async ({ manifest, archiveSHA256 }) => ({ ...summary(manifest), sha256: archiveSHA256 }));
}

export async function restoreBackup(repo, source, approved, { beforeCommit, expectedSHA256 } = {}) {
  if (approved !== true) throw new ServiceError('恢复备份需要明确确认', 403);
  return withValidatedBackup(source, async ({ manifest, records, events, staging }) => {
    const backups = path.join(repo.directory, 'backups');
    await mkdir(backups, { recursive: true, mode: 0o700 });
    const previousBackup = path.join(backups, `before-restore-${randomUUID()}.zip`);
    await createBackup(repo, previousBackup);
    const attachments = path.join(repo.directory, 'attachments', `restored-${randomUUID()}`);
    await mkdir(attachments, { recursive: true, mode: 0o700 });
    let committed = false;
    try {
      for (const entry of manifest.files.filter(item => item.attachmentId))
        await rename(path.join(staging, entry.path), path.join(attachments, path.basename(entry.path)));
      beforeCommit?.();
      repo.transaction(() => {
        repo.db.exec('DELETE FROM records; DELETE FROM events;');
        const insert = repo.db.prepare('INSERT INTO records(kind,id,data) VALUES(?,?,?)');
        for (const row of records) {
          const value = JSON.parse(row.data);
          if (row.kind === 'attachment') value.path = path.join(attachments, path.basename(filenameFor(row.id)));
          if (row.kind === 'draft' && value.status === 'sending') value.status = 'uncertain';
          if (row.kind === 'job' && value.status === 'running') {
            value.status = ['classify', 'attachmentBatch'].includes(value.task) ? 'paused' : 'failed';
            value.error = '备份恢复了未完成任务，请检查后继续。';
            for (const item of value.attachmentItems || []) if (item.status === 'running') item.status = 'pending';
          }
          if (row.kind === 'sync' && value.status === 'running') value.status = 'paused';
          insert.run(row.kind, row.id, JSON.stringify(value));
        }
        const event = repo.db.prepare('INSERT INTO events(id,time,type,detail) VALUES(?,?,?,?)');
        for (const row of events) event.run(row.id, row.time, row.type, row.detail);
        repo.rebuildSearch?.();
        repo.event('restore', '已恢复完整备份，恢复前的数据已另存为备份；钥匙串凭证保持原状');
      });
      committed = true;
      return { ok: true, previousBackup, ...summary(manifest) };
    } finally { if (!committed) await rm(attachments, { recursive: true, force: true }); }
  }, expectedSHA256);
}
