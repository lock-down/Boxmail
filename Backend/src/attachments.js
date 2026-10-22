import { readFile, writeFile, mkdir } from 'node:fs/promises';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import mammoth from 'mammoth';
import ExcelJS from 'exceljs';
import { PDFParse } from 'pdf-parse';
import { ServiceError } from './validation.js';
import { isPresentation, presentationText, presentationPDF } from './presentations.js';

export async function extractText(buffer, name, contentType = '') {
  const ext = path.extname(name).toLowerCase();
  if (['.txt', '.csv', '.md', '.json', '.log'].includes(ext))
    return buffer.toString('utf8').slice(0, 200000);
  if (ext === '.pdf') {
    const parser = new PDFParse({ data: new Uint8Array(buffer) });
    try {
      return (await parser.getText()).text.slice(0, 200000);
    } finally {
      await parser.destroy();
    }
  }
  if (ext === '.docx')
    return (await mammoth.extractRawText({ buffer })).value.slice(0, 200000);
  if (isPresentation({ name, contentType }))
    return presentationText(buffer, { name, contentType });
  if (ext === '.xlsx') {
    const workbook = new ExcelJS.Workbook();
    await workbook.xlsx.load(buffer);
    let text = '';
    for (const sheet of workbook.worksheets) {
      text += `\n[${sheet.name}]\n`;
      sheet.eachRow((row) => {
        if (text.length < 200000)
          text +=
            row.values
              .slice(1)
              .map((v) =>
                typeof v === 'object' ? JSON.stringify(v) : (v ?? ''),
              )
              .join('\t') + '\n';
      });
    }
    return text.slice(0, 200000);
  }
  return '';
}
export async function saveAttachment(
  repo,
  messageId,
  name,
  buffer,
  contentType = 'application/octet-stream',
) {
  if (buffer.length > 25 * 1024 * 1024)
    throw new ServiceError('单个附件超过 25 MB');
  const id = randomUUID();
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
  await writeFile(file, buffer, { mode: 0o600 });
  let text = '',
    parseError = '';
  try {
    text = await extractText(buffer, name, contentType);
  } catch {
    parseError = '文件无法解析，可下载原文件查看';
  }
  return repo.put('attachment', {
    id,
    messageId,
    name: path.basename(name),
    size: buffer.length,
    contentType,
    path: file,
    text,
    analysis: null,
    parseError,
    date: new Date().toISOString(),
  });
}
export async function attachmentBytes(repo, id) {
  const a = repo.get('attachment', id);
  if (!a) throw new ServiceError('附件不存在', 404);
  return { metadata: a, buffer: await readFile(a.path) };
}

// A message that takes over attachments saved for something else (for example a draft being
// sent) becomes their new owner. `ownerId`, when given, limits the move to attachments that
// still belong to that record, so borrowed attachments (forwarded mail) keep their owner.
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
    const document = await presentationPDF(buffer, metadata, { signal });
    return { ...await renderPDFPages(document.buffer, metadata.name, 'presentation', signal), text: document.text };
  }
  if (ext === '.pdf' || metadata.contentType === 'application/pdf')
    return renderPDFPages(buffer, metadata.name, 'pdf', signal);
  if (metadata.text?.trim()) return { kind: 'text', images: [] };
  throw new ServiceError('该附件格式暂不支持模型理解，请使用 PDF、PPT、PPTX、DOCX、XLSX、文本或 JPEG、PNG、GIF、WebP 图片');
}

async function renderPDFPages(buffer, name, kind, signal) {
  const label = kind === 'presentation' ? 'PPT' : 'PDF';
  const parser = new PDFParse({ data: new Uint8Array(buffer) });
  try {
    const info = await parser.getInfo();
    if (info.total > 20) throw new ServiceError(`${label} 共 ${info.total} 页，请拆分为每份不超过 20 页后解析`);
    const details = await parser.getInfo({ parsePageInfo: true });
    const images = [];
    let bytes = 0;
    for (const page of details.pages) {
      signal?.throwIfAborted();
      const screenshot = await parser.getScreenshot({
        partial: [page.pageNumber], scale: 1800 / Math.max(page.width, page.height),
        imageDataUrl: false, imageBuffer: true,
      });
      const image = screenshot.pages[0];
      if (!image?.data?.length) throw new ServiceError(`${label} 页面无法转换，请检查文件`);
      const buffer = Buffer.from(image.data);
      bytes += buffer.length;
      if (bytes > 25 * 1024 * 1024) throw new ServiceError(`${label} 页面图片超过 25 MB，请拆分文件后解析`);
      images.push({ name: `${path.parse(name).name}-page-${image.pageNumber}.png`, contentType: 'image/png', buffer });
    }
    if (!images.length) throw new ServiceError(`${label} 没有可解析的页面`);
    return { kind, pages: info.total, images };
  } catch (error) {
    signal?.throwIfAborted();
    if (error instanceof ServiceError) throw error;
    throw new ServiceError(`${label} 无法读取，请检查文件是否损坏或受密码保护`);
  } finally { await parser.destroy(); }
}
