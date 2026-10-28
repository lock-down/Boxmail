import path from 'node:path';
import { ServiceError } from './validation.js';
import { ParserProcess } from './parser-process.js';

// A fresh subprocess releases PDF.js/canvas resources and contains native aborts.
export async function processPDF(buffer, { task = 'images', name = 'document.pdf', kind = 'pdf', signal,
  diagnostics, account, processFactory = options => new ParserProcess(options) } = {}) {
  const parser = processFactory({ signal, diagnostics, account });
  try {
    const result = await parser.run('pdf', buffer, { task, name, kind, format: 'pdf' });
    for (const image of result.images || []) image.buffer = Buffer.from(image.buffer);
    return result;
  } finally { await parser.close(); }
}

// The runner calls this function inside the isolated parser process only.
export async function parsePDF(bytes, { task = 'images', name = 'document.pdf', kind = 'pdf' } = {}) {
  // Advanced process IPC preserves Buffer. PDF.js explicitly requires a plain
  // Uint8Array, as the previous thread transfer also supplied.
  const input = new Uint8Array(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const label = kind === 'presentation' ? 'PPT' : 'PDF';
  let cleanup = async () => {};
  try {
    let result;
    if (task === 'text') {
      const { PDFParse } = await import('pdf-parse');
      const parser = new PDFParse({ data: input });
      cleanup = () => parser.destroy();
      result = { text: (await parser.getText()).text.slice(0, 200000) };
    }
    else {
      const { getDocument } = await import('pdfjs-dist/legacy/build/pdf.mjs');
      const loading = getDocument({ data: input, verbosity: 0 });
      cleanup = () => loading.destroy();
      const document = await loading.promise;
      if (document.numPages > 20) throw new ServiceError(`${label} 共 ${document.numPages} 页，请拆分为每份不超过 20 页后解析`);
      const images = [];
      let size = 0;
      for (let number = 1; number <= document.numPages; number++) {
        const page = await document.getPage(number);
        const original = page.getViewport({ scale: 1 });
        const viewport = page.getViewport({ scale: 1800 / Math.max(original.width, original.height) });
        const surface = document.canvasFactory.create(viewport.width, viewport.height);
        try {
          await page.render({ canvasContext: surface.context, viewport, canvas: surface.canvas }).promise;
          const image = new Uint8Array(surface.canvas.toBuffer('image/png'));
          size += image.byteLength;
          if (size > 25 * 1024 * 1024) throw new ServiceError(`${label} 页面图片超过 25 MB，请拆分文件后解析`);
          images.push({ name: `${path.parse(name).name}-page-${number}.png`, contentType: 'image/png', buffer: image });
        } finally {
          // Explicitly release each raster surface; waiting for GC accumulates
          // dozens of 1800px native canvases even after JS heap usage falls.
          document.canvasFactory.destroy(surface);
          page.cleanup();
        }
      }
      if (!images.length) throw new ServiceError(`${label} 没有可解析的页面`);
      result = { kind, pages: document.numPages, images };
    }
    return result;
  } finally { await cleanup().catch(() => {}); }
}
