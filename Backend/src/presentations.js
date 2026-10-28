import { textSlice } from './unicode.js';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { access, mkdtemp, mkdir, readFile, writeFile, readdir, rm, stat } from 'node:fs/promises';
import { constants, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import os from 'node:os';
import path from 'node:path';
import { convert } from 'html-to-text';
import JSZip from 'jszip';
import { Readable } from 'node:stream';
import { ServiceError } from './validation.js';

const execute = promisify(execFile);
const extensions = new Set(['.ppt', '.pptx', '.pps', '.ppsx']);
const mimeExtensions = {
  'application/vnd.ms-powerpoint': '.ppt',
  'application/vnd.openxmlformats-officedocument.presentationml.presentation': '.pptx',
  'application/vnd.openxmlformats-officedocument.presentationml.slideshow': '.ppsx',
};
const packagedRenderer = fileURLToPath(new URL('../../Runtime/BoxmailPresentationRenderer', import.meta.url));
const developmentRenderer = fileURLToPath(new URL('../../.build/debug/BoxmailPresentationRenderer', import.meta.url));
const xcodeRenderer = fileURLToPath(new URL('../../.build/out/Products/Debug/BoxmailPresentationRenderer', import.meta.url));
export function presentationRendererPath() {
  return process.env.BOXMAIL_PRESENTATION_RENDERER
    || [packagedRenderer, developmentRenderer, xcodeRenderer].find(existsSync) || developmentRenderer;
}
export function presentationExtension(file) {
  const extension = path.extname(file.name).toLowerCase();
  return extensions.has(extension) ? extension
    : mimeExtensions[file.contentType?.split(';')[0].trim().toLowerCase()] || null;
}
export function isPresentation(file) { return presentationExtension(file) !== null; }

async function command(executable, args, signal) {
  signal?.throwIfAborted();
  try {
    return await execute(executable, args, { signal, timeout: 60000, killSignal: 'SIGKILL', maxBuffer: 2 * 1024 * 1024 });
  } catch (error) {
    signal?.throwIfAborted();
    if (error.killed) throw new ServiceError('PPT 页面转换超时，请拆分文件或转换为 PDF 后理解。');
    // The native renderer only returns public messages; do not expose tool stderr or file paths.
    try {
      const result = JSON.parse(error.stdout);
      if (typeof result.error === 'string') throw new ServiceError(result.error);
    } catch (parsed) { if (parsed instanceof ServiceError) throw parsed; }
    throw new ServiceError('PPT 无法读取，请检查文件是否损坏或受密码保护，也可转换为 PDF 后理解。');
  }
}

async function prepare(buffer, file, { signal, render = false } = {}) {
  signal?.throwIfAborted();
  const extension = presentationExtension(file);
  if (!extension) throw new ServiceError('此文件不是 PPT 或 PPTX 演示文稿');
  if (buffer.length > 25 * 1024 * 1024) throw new ServiceError('单个附件超过 25 MB');
  const directory = await mkdtemp(path.join(os.tmpdir(), 'boxmail-presentation-'));
  try {
    const input = path.join(directory, `slides${extension}`);
    const previews = path.join(directory, 'preview');
    await mkdir(previews, { mode: 0o700 });
    let expectedPages = 0;
    if (['.pptx', '.ppsx'].includes(extension)) {
      const zip = await JSZip.loadAsync(buffer);
      const xml = await boundedXML(zip.file('ppt/presentation.xml'));
      expectedPages = (xml.match(/<(?:\w+:)?sldId\s/g) || []).length;
      if (!expectedPages) throw new ServiceError('PPTX 没有可读取的幻灯片，请检查文件。');
      if (render && expectedPages > 20)
        throw new ServiceError(`PPT 共 ${expectedPages} 页，请拆分为每份不超过 20 页后解析`);
      // Quick Look omits hidden slides. Reveal them in this temporary copy only;
      // the original attachment remains byte-for-byte unchanged.
      let changed = false;
      let xmlBytes = 0;
      for (const entry of Object.values(zip.files).filter(entry => /^ppt\/slides\/slide\d+\.xml$/.test(entry.name))) {
        signal?.throwIfAborted();
        const slide = await boundedXML(entry);
        xmlBytes += Buffer.byteLength(slide);
        if (xmlBytes > 32 * 1024 * 1024) throw new ServiceError('PPT 页面内容过大，请拆分文件后理解。');
        const visible = slide.replace(/<(?:\w+:)?sld\b[^>]*>/, tag => tag.replace(/\bshow\s*=\s*(["'])(?:0|false)\1/, 'show="1"'));
        if (visible !== slide) { changed = true; zip.file(entry.name, visible); }
      }
      if (changed) buffer = await zip.generateAsync({ type: 'nodebuffer', compression: 'DEFLATE' });
    }
    await writeFile(input, buffer, { mode: 0o600 });
    await command('/usr/bin/qlmanage', ['-p', '-o', previews, input], signal);
    const names = await readdir(previews);
    const preview = names.find(name => name.endsWith('.qlpreview'));
    if (!preview) throw new ServiceError('系统未能读取 PPT，请转换为 PDF 后理解。');
    const htmlFile = path.join(previews, preview, 'Preview.html');
    if ((await stat(htmlFile)).size > 32 * 1024 * 1024)
      throw new ServiceError('PPT 页面内容过大，请拆分文件后理解。');
    const html = await readFile(htmlFile, 'utf8');
    const text = textSlice(convert(html, { wordwrap: false, limits: { maxInputLength: 32 * 1024 * 1024 },
      selectors: [{ selector: 'img', format: 'skip' }] }), 0, 200000);
    if (!render) return { text };
    const renderer = presentationRendererPath();
    try { await access(renderer, constants.X_OK); }
    catch { throw new ServiceError('PPT 页面组件缺失，请重新构建或安装最新版 Boxmail。'); }
    const output = path.join(directory, 'slides.pdf');
    await command(renderer, [htmlFile, output, String(expectedPages), '20'], signal);
    if ((await stat(output)).size > 50 * 1024 * 1024)
      throw new ServiceError('PPT 转换后的页面超过 50 MB，请拆分文件后理解。');
    return { text, buffer: await readFile(output) };
  } catch (error) {
    signal?.throwIfAborted();
    if (error instanceof ServiceError) throw error;
    throw new ServiceError('PPT 无法读取，请检查文件是否损坏或受密码保护，也可转换为 PDF 后理解。');
  } finally { await rm(directory, { recursive: true, force: true }); }
}

async function boundedXML(entry) {
  if (!entry) throw new ServiceError('PPTX 文件结构不完整，请检查文件。');
  const chunks = [];
  let size = 0;
  for await (const chunk of Readable.wrap(entry.nodeStream())) {
    size += chunk.length;
    if (size > 2 * 1024 * 1024) throw new ServiceError('PPT 页面内容过大，请拆分文件后理解。');
    chunks.push(chunk);
  }
  return Buffer.concat(chunks).toString('utf8');
}

export async function presentationText(buffer, file, options) {
  return (await prepare(buffer, file, options)).text;
}
export async function presentationPDF(buffer, file, options) {
  return prepare(buffer, file, { ...options, render: true });
}
