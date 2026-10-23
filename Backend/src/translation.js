import { parseDocument, DomUtils } from 'htmlparser2';
import { convert } from 'html-to-text';
import { mailBody } from './mail-body.js';
import { ServiceError } from './validation.js';

const excluded = new Set(['script', 'style', 'pre', 'code', 'kbd', 'samp']);
const translatable = value => /\p{L}/u.test(value) && !/^\s*(?:https?:\/\/\S+|\S+@\S+\.\S+)\s*$/u.test(value);

export function translationDocument(message) {
  const html = message.html ? mailBody({ html: message.html }).html : '';
  const document = html ? parseDocument(html) : null;
  const nodes = [];
  const visit = node => {
    if (excluded.has(node.name)) return;
    if (node.type === 'text' && translatable(node.data)) nodes.push(node);
    for (const child of node.children || []) visit(child);
  };
  if (document) visit(document);
  // Plain-text mail keeps its line breaks and empty lines as well.
  const lines = document ? null : message.body.split(/(\r?\n)/);
  if (lines) lines.forEach((data, index) => { if (translatable(data)) nodes.push({ data, index }); });
  const segments = nodes.map((node, index) => ({ id: String(index), text: node.data }));
  const ids = new Set(segments.map(segment => segment.id));
  return {
    segments,
    render(result, complete = false) {
      const values = Array.isArray(result.segments) ? result.segments : [];
      if (complete && (values.length !== segments.length || values.some((item, index) => item?.id !== segments[index].id)))
        throw new ServiceError('译文段落不完整，请重新翻译', 502);
      const byId = new Map();
      for (const item of values) {
        if (!item || typeof item.id !== 'string' || typeof item.text !== 'string') continue;
        if (!ids.has(item.id) || byId.has(item.id)) {
          if (complete) throw new ServiceError('译文段落不完整，请重新翻译', 502);
          continue;
        }
        if (item.text.trim()) byId.set(item.id, item.text);
      }
      if (complete && byId.size !== segments.length) throw new ServiceError('译文段落不完整，请重新翻译', 502);
      nodes.forEach((node, index) => {
        const original = segments[index].text;
        const translated = byId.get(String(index));
        node.data = translated ? (original.match(/^\s*/)?.[0] || '') + translated.trim() + (original.match(/\s*$/)?.[0] || '') : original;
        if (lines) lines[node.index] = node.data;
      });
      const translatedHTML = document ? DomUtils.getOuterHTML(document, { encodeEntities: 'utf8' }) : undefined;
      return { text: document ? convert(translatedHTML, { wordwrap: false, selectors: [{ selector: 'img', format: 'skip' }] }) : lines.join(''),
        ...(translatedHTML ? { html: translatedHTML } : {}) };
    },
  };
}
