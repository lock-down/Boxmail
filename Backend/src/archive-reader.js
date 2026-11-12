import { attachmentKind } from './attachment-kind.js';
import yauzl from 'yauzl';
import path from 'node:path';
import { crc32 } from 'node:zlib';
import { ServiceError } from './validation.js';

export const ARCHIVE_LIMITS = Object.freeze({ files: 100, entries: 2048, fileBytes: 25 * 1024 * 1024, totalBytes: 100 * 1024 * 1024 });
const formats = new Map(Object.entries({
  '.txt': 'text/plain', '.md': 'text/markdown', '.csv': 'text/csv', '.json': 'application/json', '.log': 'text/plain',
  '.pdf': 'application/pdf', '.docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  '.xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  '.ppt': 'application/vnd.ms-powerpoint', '.pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  '.pps': 'application/vnd.ms-powerpoint', '.ppsx': 'application/vnd.openxmlformats-officedocument.presentationml.slideshow',
  '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.png': 'image/png', '.gif': 'image/gif', '.webp': 'image/webp',
}));
export function isArchive(file) {
  return attachmentKind(file.name, file.contentType) === 'archive';
}
function descriptor(entry, index, budget) {
  const name = entry.fileName;
  const ext = path.extname(name).toLowerCase();
  let error = null;
  if (name.length > 1000 || /[\x00-\x1f\x7f]/.test(name)) error = '文件路径无效';
  else if (((entry.externalFileAttributes >>> 16) & 0xf000) === 0xa000) error = '不处理符号链接';
  else if (entry.isEncrypted()) error = '加密文件需解密后重新上传';
  else if (!Number.isSafeInteger(entry.uncompressedSize) || entry.uncompressedSize > ARCHIVE_LIMITS.fileBytes) error = '文件解压后超过 25 MB';
  else if (budget + entry.uncompressedSize > ARCHIVE_LIMITS.totalBytes) error = '本包可处理的解压内容已达到 100 MB';
  else if (![0, 8].includes(entry.compressionMethod)) error = '不支持此压缩方式';
  else if (['.zip', '.rar', '.7z', '.tar', '.gz'].includes(ext)) error = '暂不递归处理嵌套压缩包';
  else if (!formats.has(ext)) error = '此文件格式暂不支持理解';
  return { id: String(index), path: name, name: path.posix.basename(name), size: entry.uncompressedSize,
    contentType: formats.get(ext) || 'application/octet-stream', status: error ? 'unsupported' : 'pending', error };
}
// Only the isolated parser process opens ZIPs. Files stay in memory and are never extracted to their supplied paths.
export async function readArchive(buffer, { entryId } = {}) {
  if (buffer.length > ARCHIVE_LIMITS.fileBytes) throw new ServiceError('ZIP 原文件超过 25 MB');
  let zip;
  try {
    zip = await yauzl.fromBufferPromise(buffer, { lazyEntries: true, decodeStrings: false, strictFileNames: true, validateEntrySizes: true });
    if (zip.entryCount > ARCHIVE_LIMITS.entries) throw new ServiceError('ZIP 目录条目过多，最多允许 2048 个条目');
    const entries = [], names = new Set();
    let totalFiles = 0, budget = 0, index = 0;
    for await (const entry of zip.eachEntry()) {
      const current = index++;
      // Decode raw bytes before path validation: 0x5c can be a GBK trail byte.
      entry.fileName = yauzl.getFileNameLowLevel(entry.generalPurposeBitFlag, entry.fileNameRaw, entry.extraFields, true);
      const unicodePath = entry.extraFields.some(field => field.id === 0x7075 && field.data.length >= 6
        && field.data[0] === 1 && field.data.readUInt32LE(1) === crc32(entry.fileNameRaw));
      if (!(entry.generalPurposeBitFlag & 0x800) && !unicodePath) {
        try { entry.fileName = new TextDecoder('utf-8', { fatal: true }).decode(entry.fileNameRaw); }
        catch {
          try {
            const decoded = new TextDecoder('gbk', { fatal: true }).decode(entry.fileNameRaw);
            if (/\p{Script=Han}/u.test(decoded)) entry.fileName = decoded;
          } catch { /* Retain yauzl's CP437 fallback for non-Chinese legacy names. */ }
        }
      }
      if (yauzl.validateFileName(entry.fileName)) throw new ServiceError('ZIP 目录路径不安全');
      if (entry.fileName.endsWith('/') || entry.fileName.startsWith('__MACOSX/') || path.posix.basename(entry.fileName) === '.DS_Store') continue;
      totalFiles++;
      if (!entry.fileName || entry.fileName.length > 1000 || /[\x00-\x1f\x7f]/.test(entry.fileName)
        || !Number.isSafeInteger(entry.uncompressedSize) || entry.uncompressedSize < 0) continue;
      if (entries.length >= ARCHIVE_LIMITS.files) continue;
      const item = descriptor(entry, current, budget);
      if (names.has(item.path)) { item.status = 'unsupported'; item.error = '文件路径重复，无法确定来源'; }
      names.add(item.path);
      if (item.status === 'pending') budget += item.size;
      entries.push(item);
      if (entryId === item.id) {
        if (item.error) throw new ServiceError(item.error);
        const stream = await zip.openReadStreamPromise(entry);
        const chunks = [];
        let length = 0, checksum = 0;
        for await (const chunk of stream) {
          length += chunk.length;
          if (length > ARCHIVE_LIMITS.fileBytes || length > entry.uncompressedSize) {
            stream.destroy(); throw new ServiceError('文件实际解压大小超过允许范围');
          }
          checksum = crc32(chunk, checksum);
          chunks.push(chunk);
        }
        if (length !== entry.uncompressedSize || checksum !== entry.crc32) throw new ServiceError('文件校验失败，压缩包可能损坏');
        return { ...item, buffer: Buffer.concat(chunks, length) };
      }
    }
    if (entryId !== undefined) throw new ServiceError('压缩包内文件不存在', 404);
    return { entries, totalFiles, omitted: Math.max(0, totalFiles - entries.length), limits: ARCHIVE_LIMITS };
  } catch (error) {
    if (error instanceof ServiceError) throw error;
    throw new ServiceError('ZIP 已损坏、目录路径不安全或使用了不支持的格式，请检查原文件');
  } finally { zip?.close(); }
}
