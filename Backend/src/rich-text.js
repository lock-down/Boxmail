import { Parser } from 'htmlparser2';
import { ServiceError } from './validation.js';
import { textStyle, styleAttribute, styleFromHTML, resolvedTextStyle } from './rich-text-style.js';

const escape = value => value.replace(/[&<>"']/g,
  character => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[character]);
export function safeLink(value) {
  if (typeof value !== 'string' || value.length > 4000 || /[\x00-\x20\x7f]/.test(value)) return null;
  try { return ['https:', 'http:', 'mailto:'].includes(new URL(value).protocol) ? value : null; }
  catch { return null; }
}

// A small semantic document is shared with TextKit. No HTML, external resources,
// or executable markup needs to be imported by the native editor.
export function richDocument(input) {
  if (!input || !Array.isArray(input.blocks) || input.blocks.length > 20000)
    throw new ServiceError('富文本正文格式无效');
  let characters = 0, runs = 0, serialized = 0;
  const blocks = input.blocks.map(block => {
    if (!block || !['paragraph', 'bullet', 'numbered'].includes(block.kind) || !Array.isArray(block.runs))
      throw new ServiceError('富文本段落格式无效');
    return { kind: block.kind, runs: block.runs.map(run => {
      if (!run || typeof run.text !== 'string' || /[\r\n]/.test(run.text)
        || ++runs > 100000 || (characters += run.text.length) > 500000)
        throw new ServiceError('富文本正文无效或超过 500,000 个字符');
      if (run.link != null && !safeLink(run.link)) throw new ServiceError('链接仅支持完整的 HTTP、HTTPS 或邮件地址');
      serialized += run.text.length + (run.link?.length || 0);
      if (serialized > 4 * 1024 * 1024) throw new ServiceError('富文本链接与正文总长度超过支持范围，请简化正文');
      return { text: run.text, bold: run.bold === true, italic: run.italic === true,
        ...(run.link ? { link: run.link } : {}), ...textStyle(run) };
    }).reduce((normalized, run) => {
      if (!run.text) return normalized;
      const previous = normalized.at(-1);
      if (previous && previous.bold === run.bold && previous.italic === run.italic && previous.link === run.link
        && previous.fontSize === run.fontSize && previous.color === run.color)
        previous.text += run.text;
      else normalized.push(run);
      return normalized;
    }, []) };
  });
  return { blocks };
}

export function richContent(input) {
  const richText = richDocument(input);
  let list = '', ordinal = 0;
  let previousStyle = resolvedTextStyle({});
  const html = [], text = [];
  for (const block of richText.blocks) {
    const nextList = block.kind === 'bullet' ? 'ul' : block.kind === 'numbered' ? 'ol' : '';
    if (list !== nextList) {
      if (list) html.push(`</${list}>`);
      if (nextList) html.push(`<${nextList}>`);
      list = nextList; ordinal = 0;
    }
    const markerStyle = block.runs.length ? resolvedTextStyle(block.runs[0]) : previousStyle;
    const inline = block.runs.map(run => {
      let value = escape(run.text);
      if (run.bold) value = `<strong>${value}</strong>`;
      if (run.italic) value = `<em>${value}</em>`;
      const style = styleAttribute(list ? resolvedTextStyle(run) : run);
      if (run.link) value = `<a href="${escape(run.link)}"${style}>${value}</a>`;
      else if (style) value = `<span${style}>${value}</span>`;
      return value;
    }).join('');
    html.push(list ? `<li${styleAttribute(markerStyle)}>${inline || '<br />'}</li>` : `<p>${inline || '<br />'}</p>`);
    text.push((list === 'ul' ? '• ' : list === 'ol' ? `${++ordinal}. ` : '') + block.runs.map(run => run.text).join(''));
    previousStyle = block.runs.length ? resolvedTextStyle(block.runs.at(-1)) : markerStyle;
  }
  if (list) html.push(`</${list}>`);
  return { richText, body: text.join('\n'), bodyHTML: html.join('') };
}

export function richFromHTML(html) {
  if (typeof html !== 'string' || html.length > 4 * 1024 * 1024)
    throw new ServiceError('服务器草稿正文过大，已保留本机草稿，请在网页版处理');
  const blocks = [], stack = [], lists = [];
  let current = null, suppressed = 0, depth = 0;
  const flush = () => { if (current) { blocks.push(current); current = null; } };
  const begin = () => current ||= { kind: lists.at(-1) || 'paragraph', runs: [] };
  const parser = new Parser({
    onopentag(name, attributes) {
      if (++depth > 100) throw new ServiceError('服务器草稿嵌套过深，请在网页版简化正文');
      const hidden = ['script', 'style', 'head', 'iframe', 'object'].includes(name);
      if (hidden) suppressed++;
      const previous = stack.at(-1) || {};
      stack.push({ name, hidden, bold: previous.bold || ['b', 'strong'].includes(name)
          || /font-weight\s*:\s*(?:bold|[6-9]00)/i.test(attributes.style || ''),
        italic: previous.italic || ['i', 'em'].includes(name) || /font-style\s*:\s*italic/i.test(attributes.style || ''),
        link: name === 'a' ? safeLink(attributes.href) : previous.link,
        ...styleFromHTML(name, attributes, previous) });
      if (suppressed) return;
      if (['ul', 'ol'].includes(name)) { flush(); lists.push(name === 'ul' ? 'bullet' : 'numbered'); }
      if (['p', 'div', 'li', 'blockquote', 'tr'].includes(name)) { flush(); begin(); }
      if (name === 'br') { begin(); flush(); }
    },
    ontext(value) {
      if (suppressed || !current && !value.trim()) return;
      const state = stack.at(-1) || {};
      for (const [index, part] of value.replace(/\r\n?/g, '\n').split('\n').entries()) {
        if (index) flush();
        begin().runs.push({ text: part, bold: !!state.bold, italic: !!state.italic,
          ...(state.link ? { link: state.link } : {}), fontSize: state.fontSize, color: state.color });
      }
    },
    onclosetag(name) {
      const state = stack.pop(); depth = Math.max(0, depth - 1);
      if (state?.hidden) suppressed = Math.max(0, suppressed - 1);
      if (suppressed) return;
      if (['p', 'div', 'li', 'blockquote', 'tr'].includes(name)) flush();
      if (['ul', 'ol'].includes(name)) { flush(); lists.pop(); }
    },
  }, { decodeEntities: true });
  parser.end(html); flush();
  return richContent({ blocks });
}

export function savedRichBody(input, previous = {}) {
  if (input.richText != null) return richContent(input.richText);
  if (input.bodyHTML != null) return richFromHTML(input.bodyHTML);
  if (input.body === previous?.body && previous?.richText) return richContent(previous.richText);
  return { body: String(input.body || '') };
}
