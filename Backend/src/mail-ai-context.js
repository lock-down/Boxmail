import { readFile } from 'node:fs/promises';
import { attachmentKind } from './attachment-kind.js';
import { extractContent, modelFile } from './attachments.js';
import { MAX_EXTRACTED_TEXT } from './attachment-text.js';
import { openArchive } from './archive-service.js';
import { MailContentWorker } from './mail-content-worker.js';
import { selectedModel } from './ai-models.js';
import { aiConfig, ServiceError } from './validation.js';

const unreadable = error => error instanceof ServiceError ? error.message : '原文件暂时无法读取，请重新同步或恢复附件。';
const cachedText = file => ({ text: file.text || '',
  textTruncated: file.textTruncated ?? (file.text?.length >= MAX_EXTRACTED_TEXT) });

async function fileContent(file, load, { vision, signal, diagnostics, contentWorker }) {
  const kind = attachmentKind(file.name, file.contentType);
  const visual = ['pdf', 'presentation', 'image'].includes(kind);
  const textOnly = text => ({ ...text, kind: 'text', images: [],
    ...(visual ? { reason: '当前模型仅使用提取文字，未读取页面图片与图表。' } : {}) });
  if (file.text?.trim() && (!visual || !vision)) return textOnly(cachedText(file));
  if (kind === 'image' && !vision)
    throw new ServiceError('当前模型不支持图片输入，请切换具备图片能力的模型后重新理解。');
  const buffer = await load();
  if (visual && vision) {
    const prepared = await modelFile(buffer, file, { signal, diagnostics });
    return { ...cachedText(file), ...prepared };
  }
  const text = await extractContent(buffer, file.name, file.contentType, { signal, diagnostics, contentWorker });
  if (!text.text?.trim()) throw new ServiceError('未提取到可读文字，可在原文件中核对或更换具备图片能力的模型。');
  return textOnly(text);
}

// Local preparation only: summary and reply share original sources, never per-file AI answers.
export async function prepareMailContext(repo, message, config, { signal, onProgress } = {}) {
  const vision = selectedModel(aiConfig(config)).input.includes('image');
  const images = [], attachments = [], sources = [];

  async function prepare(file, load, contentWorker) {
    const identity = { id: file.id, name: file.name };
    try {
      signal?.throwIfAborted();
      const prepared = await fileContent(file, load, { vision, signal, diagnostics: repo.diagnostics, contentWorker });
      signal?.throwIfAborted();
      const indices = prepared.images.map((_, i) => images.length + i + 1);
      images.push(...prepared.images);
      const reason = prepared.reason || (prepared.textTruncated && !indices.length ? '提取文字达到现有解析上限，仅纳入已提取部分。' : null);
      const coverage = { ...identity, status: reason ? 'partial' : 'included', reason };
      return { content: { ...coverage, text: prepared.text || '', textTruncated: !!prepared.textTruncated,
        inputKind: prepared.kind, pages: prepared.pages, imageIndices: indices }, coverage };
    } catch (error) {
      if (signal?.aborted) throw error;
      const coverage = { ...identity, status: 'unavailable', reason: unreadable(error) };
      return { content: coverage, coverage };
    }
  }

  async function archive(file) {
    const opened = await openArchive(repo, file.id, { signal, readBytes: true });
    const parser = new MailContentWorker({ signal, diagnostics: repo.diagnostics });
    const entries = [], coverage = [];
    try {
      for (const entry of opened.archive.entries) {
        signal?.throwIfAborted();
        const identity = { id: `${file.id}:${entry.id}`, name: entry.path };
        if (entry.status === 'unsupported') {
          const skipped = { ...identity, status: 'unavailable', reason: entry.error };
          entries.push(skipped); coverage.push(skipped);
          continue;
        }
        onProgress?.(`正在读取：${file.name}/${entry.path}`);
        const prepared = await prepare({ ...entry, ...identity }, async () => {
          const result = await parser.run('archive-entry', opened.buffer, { entryId: entry.id, format: 'zip' });
          return Buffer.from(result.buffer);
        }, parser);
        entries.push(prepared.content); coverage.push(prepared.coverage);
      }
    } finally { await parser.close(); }
    const complete = !opened.archive.omitted && coverage.length > 0 && coverage.every(item => item.status === 'included');
    const source = { id: file.id, name: file.name, status: complete ? 'included' : 'partial',
      reason: opened.archive.omitted ? `${opened.archive.omitted} 个包内文件超出现有 ZIP 解析范围，未纳入。`
        : !coverage.length ? '压缩包内没有可读文件。' : complete ? null : '部分包内文件未完整纳入，请展开查看。' };
    return { content: { ...source, inputKind: 'archive', entries }, coverage: { ...source, entries: coverage } };
  }

  for (const id of message.attachmentIds || []) {
    signal?.throwIfAborted();
    const file = repo.get('attachment', id);
    onProgress?.(`正在读取附件：${file?.name || '附件'}`);
    let prepared;
    if (!file || file.messageId !== message.id) {
      const source = { id, name: file?.name || '附件', status: 'unavailable', reason: '附件已移除或不属于本封邮件。' };
      prepared = { content: source, coverage: source };
    } else if (attachmentKind(file.name, file.contentType) === 'archive') {
      try { prepared = await archive(file); }
      catch (error) {
        if (signal?.aborted) throw error;
        const source = { id, name: file.name, status: 'unavailable', reason: unreadable(error) };
        prepared = { content: source, coverage: source };
      }
    } else {
      prepared = await prepare(file, () => readFile(file.path, { signal }));
    }
    attachments.push(prepared.content); sources.push(prepared.coverage);
  }
  return {
    content: { sender: message.sender, senderEmail: message.senderEmail, to: message.to, cc: message.cc,
      subject: message.subject, date: message.date, body: message.body, attachments,
      imageOrder: 'imageIndices 从 1 起对应本次输入的图片顺序；每份文档的页面依次排列。' },
    images,
    coverage: { attachments: sources, partial: sources.some(source => source.status !== 'included') },
  };
}
