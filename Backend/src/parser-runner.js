import { ServiceError } from './validation.js';
import { Worker } from 'node:worker_threads';
import { rmSync } from 'node:fs';
// This module is launched only through ParserProcess, without app credentials.
// A dropped IPC channel means the owner disappeared: do not leave parser children.
if (!process.send || process.env.BOXMAIL_PARSER_CHILD !== '1') throw new Error('Parser IPC is required');
new Worker(new URL('./parser-owner-watch.js', import.meta.url), {
  workerData: { fd: 4, directory: process.env.TMPDIR, rssLimitBytes: Number(process.env.BOXMAIL_PARSER_RSS_LIMIT) },
}).unref();
process.on('disconnect', () => {
  try { rmSync(process.env.TMPDIR, { recursive: true, force: true }); } catch {}
  try { process.kill(-process.pid, 'SIGKILL'); } catch { process.exit(0); }
});
process.on('message', async message => {
  if (message?.type !== 'parse') return;
  try {
    const { task, buffer, options } = message;
    let result;
    if (['mime', 'docx', 'xlsx'].includes(task)) {
      const { parseMailContent } = await import('./mail-content-worker.js');
      result = await parseMailContent(task, buffer);
    } else if (task === 'pdf') {
      const { parsePDF } = await import('./pdf-processing.js');
      result = await parsePDF(buffer, options);
    } else if (task === 'presentation-text') {
      const { presentationText } = await import('./presentations.js');
      result = { text: await presentationText(buffer, { name: options.name, contentType: options.contentType }) };
    } else if (task === 'presentation') {
      const { presentationPDF } = await import('./presentations.js');
      const { parsePDF } = await import('./pdf-processing.js');
      const document = await presentationPDF(buffer, { name: options.name, contentType: options.contentType });
      result = { ...await parsePDF(document.buffer, { name: options.name, kind: 'presentation' }), text: document.text };
    } else if (task === 'workbook-preview') {
      const { renderWorkbookPreview } = await import('./workbook-preview.js');
      result = { html: await renderWorkbookPreview(buffer) };
    } else throw new Error('Unknown parser task');
    process.send({ type: 'result', result, rss: process.memoryUsage.rss() });
  } catch (error) {
    // Exception messages can contain document content; return a classification only.
    process.send({ type: 'result', error: error instanceof ServiceError
      ? { message: error.message, status: error.status } : {} });
  }
});
