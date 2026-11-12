import path from 'node:path';

export const extensions = {
  zip: 'archive', pdf: 'pdf', doc: 'word', docx: 'word', odt: 'word', rtf: 'word',
  xls: 'spreadsheet', xlsx: 'spreadsheet', csv: 'spreadsheet', ods: 'spreadsheet',
  ppt: 'presentation', pptx: 'presentation', pps: 'presentation', ppsx: 'presentation',
  jpg: 'image', jpeg: 'image', png: 'image', gif: 'image', webp: 'image',
  txt: 'text', md: 'text', json: 'text', log: 'text',
};
const mimeKinds = {
  'application/zip': 'archive', 'application/x-zip-compressed': 'archive', 'application/pdf': 'pdf',
  'application/msword': 'word', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document': 'word',
  'application/vnd.ms-excel': 'spreadsheet', 'text/csv': 'spreadsheet',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': 'spreadsheet',
  'application/vnd.ms-powerpoint': 'presentation',
  'application/vnd.openxmlformats-officedocument.presentationml.presentation': 'presentation',
  'application/vnd.openxmlformats-officedocument.presentationml.slideshow': 'presentation',
  'image/jpeg': 'image', 'image/png': 'image', 'image/gif': 'image', 'image/webp': 'image',
  'text/plain': 'text', 'text/markdown': 'text', 'application/json': 'text',
};

export function attachmentKind(name, mime) {
  return extensions[path.extname(name || '').slice(1).toLowerCase()]
    || mimeKinds[(mime || '').split(';')[0].trim().toLowerCase()] || 'other';
}
