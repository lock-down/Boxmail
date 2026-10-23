import { Worker, isMainThread, parentPort, workerData } from 'node:worker_threads';
import path from 'node:path';
import { ServiceError } from './validation.js';

// A fresh worker releases PDF.js/canvas resources after each document and keeps
// page rasterization off the HTTP event loop. CPU accounting still includes it.
export async function processPDF(buffer, { task = 'images', name = 'document.pdf', kind = 'pdf', signal } = {}) {
  signal?.throwIfAborted();
  const bytes = new Uint8Array(buffer);
  const worker = new Worker(new URL(import.meta.url), {
    workerData: { bytes, task, name, kind }, transferList: [bytes.buffer],
  });
  let timer, abort;
  try {
    const result = await new Promise((resolve, reject) => {
      abort = () => reject(signal.reason);
      signal?.addEventListener('abort', abort, { once: true });
      timer = setTimeout(() => reject(new ServiceError('PDF 页面处理超时，请拆分文件后重试', 502)), 60000);
      worker.once('message', message => message.error
        ? reject(new ServiceError(message.error.message, message.error.status)) : resolve(message.result));
      worker.once('error', () => reject(new ServiceError('PDF 页面处理未完成，请检查文件后重试', 502)));
      worker.once('exit', () => reject(new ServiceError('PDF 页面处理已中断，请重试', 502)));
      if (signal?.aborted) abort();
    });
    if (result.images) for (const image of result.images)
      image.buffer = Buffer.from(image.buffer.buffer, image.buffer.byteOffset, image.buffer.byteLength);
    return result;
  } finally {
    clearTimeout(timer);
    signal?.removeEventListener('abort', abort);
    await worker.terminate();
  }
}

if (!isMainThread) {
  const { bytes, task, name, kind } = workerData;
  const label = kind === 'presentation' ? 'PPT' : 'PDF';
  let cleanup = async () => {};
  try {
    let result;
    if (task === 'text') {
      const { PDFParse } = await import('pdf-parse');
      const parser = new PDFParse({ data: bytes });
      cleanup = () => parser.destroy();
      result = { text: (await parser.getText()).text.slice(0, 200000) };
    }
    else {
      const { getDocument } = await import('pdfjs-dist/legacy/build/pdf.mjs');
      const loading = getDocument({ data: bytes, verbosity: 0 });
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
    await cleanup();
    parentPort.postMessage({ result }, (result.images || []).map(image => image.buffer.buffer));
  } catch (error) {
    await cleanup().catch(() => {});
    parentPort.postMessage({ error: { message: error instanceof ServiceError ? error.message
      : `${label} 无法读取，请检查文件是否损坏或受密码保护`, status: error.status || 400 } });
  }
  parentPort.close();
}
