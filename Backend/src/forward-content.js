import { randomUUID } from 'node:crypto';
import { mailBody } from './mail-body.js';
import { ServiceError } from './validation.js';

const escape = value => String(value || '').replace(/[&<>"']/g,
  character => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[character]);

export function forwardText(message) {
  return `---------- 转发邮件 ----------\n发件人：${message.sender} <${message.senderEmail}>\n日期：${message.date}\n主题：${message.subject}\n\n${message.body}`;
}

export function forwardedFields(message) {
  const html = mailBody({ html: message.html, text: message.body }).html;
  if (!html) return {};
  return {
    forwardedText: forwardText(message),
    forwardedHTML: `<div style="border-top:1px solid #e9edf2;margin-top:20px;padding-top:16px;font-family:Arial,sans-serif;font-size:13px;line-height:1.6">`
      + `<div>---------- 转发邮件 ----------</div><div>发件人：${escape(message.sender)} &lt;${escape(message.senderEmail)}&gt;</div>`
      + `<div>日期：${escape(message.date)}</div><div>主题：${escape(message.subject)}</div></div>`
      + `<div style="margin-top:16px">${html}</div>`,
  };
}

// Upgrade only an intact legacy quotation; never replace edits inside old mail.
export function upgradeForwardDraft(draft, message) {
  if (draft.forwardedHTML || !/^(?:fwd?|转发):/i.test(draft.subject || '')) return draft;
  message = typeof message === 'function' ? message() : message;
  if (!message?.html) return draft;
  const suffix = '\n\n' + forwardText(message);
  if (!draft.body.endsWith(suffix)) return draft;
  const fields = forwardedFields(message);
  return fields.forwardedHTML ? { ...draft, body: draft.body.slice(0, -suffix.length), ...fields } : draft;
}

export function savedForwardFields(input, previous = {}) {
  previous ??= {};
  const html = input.forwardedHTML === undefined ? previous.forwardedHTML : input.forwardedHTML;
  const text = input.forwardedText === undefined ? previous.forwardedText : input.forwardedText;
  if (html == null && text == null) return {};
  if (typeof html !== 'string' || typeof text !== 'string'
    || html.length > 32 * 1024 * 1024 || text.length > 32 * 1024 * 1024)
    throw new ServiceError('转发原文格式无效或超过 32 MB，请重新转发或缩小原邮件');
  return { forwardedHTML: mailBody({ html, text }).html, forwardedText: text };
}

export function draftContent(draft) {
  const text = [draft.body, draft.forwardedText].filter(value => typeof value === 'string' && value.length).join('\n\n');
  if (!draft.forwardedHTML) return { text };
  const introduction = `<div style="font-family:Arial,sans-serif;font-size:14px;line-height:1.6;white-space:pre-wrap">${escape(draft.body)}</div>`;
  return { text, html: introduction + draft.forwardedHTML };
}

// Email clients commonly block data URLs. Send local images as MIME CID parts;
// reuse an existing attached image when its bytes already match the original.
export function inlineForwardImages(html, attachments) {
  if (!html) return undefined;
  const images = new Map();
  return html.replace(/src="data:(image\/(?:png|jpeg|gif|webp));base64,([^"]+)"/gi, (source, contentType, data) => {
    const key = contentType.toLowerCase() + ':' + data;
    if (!images.has(key)) {
      const content = Buffer.from(data, 'base64');
      let attachment = attachments.find(item => item.contentType === contentType && item.content.equals(content));
      if (!attachment) {
        attachment = { filename: `forwarded-image-${images.size + 1}.${contentType.split('/')[1]}`, contentType, content };
        attachments.push(attachment);
      }
      attachment.cid ||= `${randomUUID()}@boxmail.inline`;
      attachment.contentDisposition = 'inline';
      images.set(key, attachment.cid);
    }
    return `src="cid:${images.get(key)}"`;
  });
}
