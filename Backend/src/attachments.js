import { readFile, writeFile, mkdir } from 'node:fs/promises';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import mammoth from 'mammoth';
import ExcelJS from 'exceljs';
import { PDFParse } from 'pdf-parse';
import { ServiceError } from './validation.js';

export async function extractText(buffer, name) {
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
    text = await extractText(buffer, name);
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
