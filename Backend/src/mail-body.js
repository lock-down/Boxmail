import sanitizeHtml from 'sanitize-html';
import { convert } from 'html-to-text';

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

export function mailBody(parsed) {
  const html = typeof parsed.html === 'string' ? sanitizeHtml(parsed.html, {
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
  }).trim() : '';
  const text = typeof parsed.text === 'string' ? parsed.text : '';
  const body = text.trim() ? text : convert(html, {
    wordwrap: false,
    selectors: [{ selector: 'img', format: 'skip' }],
  });
  return {
    body, html, bodyVersion: MAIL_BODY_VERSION,
    hasRemoteImages: /<img\b[^>]*\bsrc="https?:\/\//i.test(html),
    preview: body.replace(/\s+/g, ' ').trim().slice(0, 140) || (/<img\b/i.test(html) ? '图片邮件' : ''),
  };
}
