import { validateArchiveDocument } from './archive-summary.js';

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
