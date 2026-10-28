import { textSlice } from './unicode.js';
import { ParserProcess } from './parser-process.js';

// Keep the public sync helper, but use a process boundary for fatal native errors.
export class MailContentWorker extends ParserProcess {
  get worker() { return this.child; }
  async run(task, buffer, options = {}) {
    const result = await super.run(task, buffer, options);
    for (const attachment of result.parsed?.attachments || [])
      attachment.content = Buffer.from(attachment.content);
    return result;
  }
}

// Invoked only inside parser-runner. No office parser is loaded by the backend.
export async function parseMailContent(task, buffer) {
  if (task === 'mime') {
    const [{ simpleParser }, { mailBody }] = await Promise.all([import('mailparser'), import('./mail-body.js')]);
    const full = await simpleParser(buffer, { skipHtmlToText: true, skipTextToHtml: true });
    const parsed = Object.fromEntries(['from', 'to', 'cc', 'replyTo', 'date', 'messageId', 'subject',
      'inReplyTo', 'references'].map(key => [key, full[key]]));
    parsed.attachments = (full.attachments || []).map(({ filename, content, contentType }) =>
      ({ filename, content, contentType }));
    return { parsed, content: mailBody(full) };
  }
  if (task === 'docx') {
    const { default: mammoth } = await import('mammoth');
    return { text: textSlice((await mammoth.extractRawText({ buffer })).value, 0, 200000) };
  }
  if (task === 'xlsx') {
    const { default: ExcelJS } = await import('exceljs');
    const workbook = new ExcelJS.Workbook();
    await workbook.xlsx.load(buffer);
    let text = '';
    for (const sheet of workbook.worksheets) {
      text += `\n[${sheet.name}]\n`;
      sheet.eachRow(row => {
        if (text.length < 200000) text += row.values.slice(1)
          .map(value => typeof value === 'object' ? JSON.stringify(value) : (value ?? '')).join('\t') + '\n';
      });
    }
    return { text: textSlice(text, 0, 200000) };
  }
  throw new Error('Unknown parser task');
}
