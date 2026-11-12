import { ServiceError } from './validation.js';

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
export function archiveSummaryText(summary, archive) {
  const paths = new Map(archive.entries.map(entry => [entry.id, entry.path]));
  const section = (title, items, field) => items.length ? `\n\n## ${title}\n${items.map(item =>
    `- ${item[field]}\n  来源：${item.entryIds.map(id => paths.get(id)).join('、')}`).join('\n')}` : '';
  const done = archive.entries.filter(entry => entry.status === 'completed').length;
  return `## 资料包总览\n${summary.overview}\n\n已理解 ${done}/${archive.totalFiles} 个文件，未处理 ${archive.totalFiles - done} 个。`
    + section('文件归类', summary.groups, 'title') + section('关联、差异与待确认事项', summary.findings, 'text')
    + section('下一步行动', summary.actions, 'text');
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
