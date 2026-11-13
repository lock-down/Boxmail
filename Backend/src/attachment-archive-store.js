import { ServiceError } from './validation.js';

export function usableArchive(value) {
  if (!value) return null;
  try { validateArchiveDocument(value); return value; }
  catch { return null; } // Derived caches must never prevent loading original files.
}

// Archive details are loaded on demand. List/search paths only touch this bounded projection.
export function archiveProjection(archive) {
  return { totalFiles: archive.totalFiles, status: archive.status,
    completedCount: archive.entries?.filter(entry => entry.status === 'completed').length || 0,
    searchText: (archive.entries || []).map(entry => entry.path).join('\n') };
}
export function storeAttachmentArchive(repo, value) {
  const { archive: candidate, ...attachment } = value;
  const archive = usableArchive(candidate);
  if (archive) {
    repo.put('archive', { ...archive, id: value.id });
    attachment.archiveInfo = archiveProjection(archive);
  } else {
    repo.remove('archive', value.id);
    delete attachment.archiveInfo;
  }
  return attachment;
}
export function loadAttachmentArchive(repo, value) {
  if (!value) return value;
  const { archive: embedded, archiveInfo, ...attachment } = value;
  const archive = usableArchive(embedded) || (archiveInfo ? usableArchive(repo.get('archive', value.id)) : null);
  return archive ? { ...attachment, archiveInfo: archiveProjection(archive), archive } : attachment;
}

export function migrateAttachmentArchives(repo) {
  const ids = repo.db.prepare("SELECT id FROM records WHERE kind='attachment' AND json_type(data,'$.archive')='object'").all();
  for (const { id } of ids) repo.transaction(() => repo.put('attachment', repo.get('attachment', id)));
  // Lightweight consistency repair: don't deserialize analysis just to remove
  // projections whose detail record is missing or has no manifest.
  repo.db.prepare(`UPDATE records AS a SET data=json_remove(data,'$.archiveInfo')
    WHERE kind='attachment' AND json_type(data,'$.archiveInfo') IS NOT NULL
    AND NOT EXISTS(SELECT 1 FROM records d WHERE d.kind='archive' AND d.id=a.id
      AND json_type(d.data,'$.entries')='array')`).run();
}

export function recoverInterruptedArchives(repo) {
  for (const {id} of repo.db.prepare("SELECT id FROM records WHERE kind='attachment' AND json_extract(data,'$.archiveInfo.status')='running'").all()) {
    const file = repo.get('attachment', id);
    if (!file) continue;
    if (!file.archive?.entries) { repo.put('attachment', file); continue; }
    const archive = file.archive.status === 'running' ? { ...file.archive, status: 'paused',
      entries: file.archive.entries.map(entry => entry.status === 'running' ? { ...entry, status: 'pending' } : entry) } : file.archive;
    repo.put('attachment', { ...file, archive });
  }
}
// References are validated against the current manifest, never accepted as arbitrary paths or URLs.
export function archiveSummary(result, archive) {
  const known = new Set(archive.entries.map(entry => entry.id));
  const understood = new Set(archive.entries.filter(entry => entry.status === 'completed').map(entry => entry.id));
  const fail = () => { throw new ServiceError('资料包汇总的来源引用无效，可重试汇总', 502); };
  if (typeof result.overview !== 'string' || !result.overview.trim() || result.overview.length > 4000) fail();
  function items(name, field, allowed) {
    const rows = result[name];
    if (!Array.isArray(rows) || rows.length > 100) fail();
    return rows.map(row => {
      if (!row || typeof row[field] !== 'string' || !row[field].trim() || row[field].length > 2000
        || !Array.isArray(row.entryIds) || !row.entryIds.length || row.entryIds.some(id => !allowed.has(id))) fail();
      return { [field]: row[field], entryIds: [...new Set(row.entryIds)] };
    });
  }
  return { overview: result.overview, groups: items('groups', 'title', known),
    findings: items('findings', 'text', understood), actions: items('actions', 'text', understood) };
}

export function validateArchiveDocument(value) {
  const fail = () => { throw new ServiceError('备份中的压缩包目录或来源记录无效'); };
  if (!value || !/^[a-f0-9]{64}$/.test(value.hash) || !['pending','running','paused','partial','completed'].includes(value.status)
    || !Number.isSafeInteger(value.totalFiles) || value.totalFiles < 0 || value.totalFiles > 2048
    || !Array.isArray(value.entries) || value.entries.length > 100 || value.totalFiles < value.entries.length
    || value.omitted !== value.totalFiles - value.entries.length) fail();
  const ids = new Set();
  for (const entry of value.entries) {
    if (!entry || typeof entry.id !== 'string' || !/^\d{1,4}$/.test(entry.id) || ids.has(entry.id)
      || !['path','name','contentType','status'].every(key => typeof entry[key] === 'string')
      || !entry.path || entry.path.length > 1000 || /^[\\/]|^[a-z]:|[\x00-\x1f\x7f]/i.test(entry.path)
      || entry.path.includes('\\') || entry.path.split('/').includes('..') || entry.name.length > 1000 || entry.contentType.length > 1024
      || !['pending','running','completed','failed','unsupported'].includes(entry.status)
      || !Number.isSafeInteger(entry.size) || entry.size < 0
      || entry.analysis != null && (typeof entry.analysis !== 'string' || entry.analysis.length > 20000)
      || entry.error != null && (typeof entry.error !== 'string' || entry.error.length > 2000)) fail();
    ids.add(entry.id);
  }
  if (value.summary != null) archiveSummary(value.summary, value);
}