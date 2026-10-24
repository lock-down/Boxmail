import sanitizeHtml from 'sanitize-html';
import { convert } from 'html-to-text';

const signatureNames = new Set([
  'gmail_signature', 'moz-signature', 'qqmail_signature', 'netease_mail_signature',
  'foxmail-signature', 'email-signature', 'mail-signature', 'signature',
]);
const replyHeader = /^(?:On .+wrote:|在.+写道[:：]|[-_—=]{2,}\s*(?:original message|forwarded message|原始邮件|转发邮件)|(?:from|发件人)\s*[:：])/i;
const signatureDetails = /(?:[\w.+-]+@[\w.-]+|(?:电话|手机|传真|地址|邮箱|tel|phone|mobile|fax|e-?mail)\s*[:：]|(?:有限(?:责任)?公司|股份有限公司)|\b(?:Co\.,?\s*Ltd\.?|www\.[\w.-]+))/i;
const mobileSignature = /^(?:Sent from my\b|Sent via\b|Get Outlook for\b|发自我的|来自我的)/i;
const signoffLine = /^(?:best regards|kind regards|regards|sincerely|祝好|此致|敬礼)[,，.!！。]?$/i;

function lineContent(line) {
  const match = /^(\s*(?:>\s*)*)([\s\S]*)$/.exec(line);
  return { depth: (match[1].match(/>/g) || []).length, text: match[2].trim() };
}

function withoutSignatures(text, sender) {
  const lines = text.replace(/\r\n?|\u2028|\u2029/g, '\n').split('\n'), visible = [];
  let signatureDepth = null;
  for (let index = 0; index < lines.length; index++) {
    const current = lineContent(lines[index]);
    // A signature ends at the next quoted message, not at the end of the reply chain.
    if (replyHeader.test(current.text)) {
      signatureDepth = null;
      visible.push(lines[index]);
      continue;
    }
    if (signatureDepth !== null && current.depth !== signatureDepth)
      signatureDepth = null;
    if (signatureDepth !== null) continue;
    const separator = /^(?:[-_—–=]\s*){5,}/.test(current.text);
    const following = [];
    if (separator || (sender && signoffLine.test(current.text))) {
      for (const line of lines.slice(index + 1, index + 11)) {
        const next = lineContent(line);
        if (replyHeader.test(next.text) || next.depth !== current.depth) break;
        following.push(next.text);
      }
    }
    const signoff = signoffLine.test(current.text) && sender && following.find(Boolean) === sender.trim();
    if (current.text === '--' || mobileSignature.test(current.text) || signoff
      || (separator && signatureDetails.test([current.text, ...following].join('\n')))) {
      signatureDepth = current.depth;
      continue;
    }
    visible.push(lines[index]);
  }
  return visible.join('\n');
}

// Previews are a display projection. The original body, HTML and quoted history
// remain untouched, including messages cached before signature filtering existed.
export function mailPreviewText(message) {
  let body = message.body || '';
  let imageOnly = false;
  if (message.html && (!body.trim() || /\b(?:class|id)\s*=\s*["'][^"']*signature/i.test(message.html))) {
    let removed = false;
    const html = sanitizeHtml(message.html, {
      allowedTags: [...sanitizeHtml.defaults.allowedTags, 'img'],
      allowedAttributes: { '*': ['class', 'id'] },
      exclusiveFilter: frame => {
        const names = `${frame.attribs.class || ''} ${frame.attribs.id || ''}`.toLowerCase().split(/\s+/);
        if (!names.some(name => signatureNames.has(name))) return false;
        removed = true;
        return true;
      },
    });
    if (removed || !body.trim()) body = convert(html, {
      wordwrap: false, selectors: [{ selector: 'img', format: 'skip' }],
    });
    imageOnly = /<img\b/i.test(html);
  }
  return withoutSignatures(body, message.sender).trim()
    || (imageOnly ? '图片邮件' : '');
}

export function mailPreview(message) {
  const text = mailPreviewText(message);
  const readable = text.replace(/\[https?:\/\/[^\]\s]+\]/gi, '')
    .replace(/https?:\/\/[^\s<>\[\]\p{Script=Han}，。；！？、）】“”]+/giu, '').replace(/\s+/g, ' ').trim();
  // Link-only messages still need a useful preview. Search retains all URLs.
  return (readable || text.replace(/\s+/g, ' ').trim()).slice(0, 140);
}
