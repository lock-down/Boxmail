import { textSlice } from './unicode.js';
import sanitizeHtml from 'sanitize-html';
import { convert } from 'html-to-text';
import { Parser } from 'htmlparser2';

export const MAIL_BODY_VERSION = 1;
const cssValue = /^(?!.*(?:url|expression)\s*\()[\w\s#.,%()'"-]+$/i;
const styleNames = [
  'color', 'background-color', 'font-family', 'font-size', 'font-weight', 'font-style',
  'line-height', 'text-align', 'text-decoration', 'letter-spacing', 'white-space',
  'vertical-align', 'display', 'float', 'clear', 'width', 'max-width', 'min-width',
  'height', 'max-height', 'min-height', 'margin', 'margin-top', 'margin-right',
  'margin-bottom', 'margin-left', 'padding', 'padding-top', 'padding-right',
  'padding-bottom', 'padding-left', 'border', 'border-width', 'border-color',
  'border-style', 'border-radius', 'border-top', 'border-right', 'border-bottom',
  'border-left', 'border-collapse', 'border-spacing', 'table-layout', 'word-break',
  'overflow-wrap',
];

// Streaming tokenization never walks an untrusted DOM recursively. Deep mail
// remains readable as text, including on the forward/translation request paths.
export function inspectMailHTML(html) {
  let depth = 0, tooDeep = false, suppressed = 0;
  const text = [];
  const parser = new Parser({
    onopentag(name) { depth++; tooDeep ||= depth > 100; if (['script', 'style'].includes(name)) suppressed++; },
    ontext(value) { if (!suppressed) text.push(value); },
    onclosetag(name) {
      depth = Math.max(0, depth - 1);
      if (['script', 'style'].includes(name)) suppressed = Math.max(0, suppressed - 1);
      if (!suppressed && ['p', 'div', 'br', 'tr', 'li'].includes(name)) text.push('\n');
    },
  }, { decodeEntities: true });
  parser.end(html);
  return { tooDeep, text: text.join('').trim() };
}

export function mailBody(parsed) {
  const source = typeof parsed.html === 'string' ? parsed.html : '';
  const inspected = inspectMailHTML(source);
  let html = '';
  try { html = source && !inspected.tooDeep ? sanitizeHtml(source, {
    nestingLimit: 100,
    allowedTags: [...sanitizeHtml.defaults.allowedTags, 'img', 'font', 'center'],
    allowedAttributes: {
      '*': ['style', 'class', 'align', 'valign', 'width', 'height', 'bgcolor', 'dir'],
      a: ['href', 'title'],
      img: ['src', 'alt', 'title', 'width', 'height'],
      table: ['cellpadding', 'cellspacing', 'border'],
      td: ['colspan', 'rowspan'], th: ['colspan', 'rowspan'],
      font: ['color', 'size', 'face'],
    },
    allowedStyles: { '*': Object.fromEntries(styleNames.map(name => [name, [cssValue]])) },
    allowedSchemes: ['https', 'http', 'mailto'],
    allowedSchemesByTag: { img: ['https', 'http', 'data'] },
    allowProtocolRelative: false,
    transformTags: {
      img: (tagName, attributes) => {
        if (/^data:/i.test(attributes.src || '') && !/^data:image\/(png|jpeg|gif|webp);base64,/i.test(attributes.src))
          delete attributes.src;
        if (/^\/\//.test(attributes.src || '')) attributes.src = `https:${attributes.src}`;
        return { tagName, attribs: attributes };
      },
    },
  }).trim() : ''; }
  catch (error) { if (!(error instanceof RangeError)) throw error; }
  const text = typeof parsed.text === 'string' ? parsed.text : '';
  const body = text.trim() ? text : !html ? inspected.text : convert(html, {
    wordwrap: false,
    limits: { maxDepth: 100 },
    selectors: [{ selector: 'img', format: 'skip' }],
  });
  return {
    body, html, bodyVersion: MAIL_BODY_VERSION,
    hasRemoteImages: /<img\b[^>]*\bsrc="https?:\/\//i.test(html),
    preview: textSlice(body.replace(/\s+/g, ' ').trim(), 0, 140) || (/<img\b/i.test(html) ? '图片邮件' : ''),
  };
}
