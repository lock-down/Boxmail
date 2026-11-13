import { parseSearch } from './search-query.js';

// Display projections must stay bounded even when a real message has thousands
// of recipients. The original record remains available through the detail API.
export const MESSAGE_HEADER_LIMITS = Object.freeze({
  to: 2048, cc: 2048, bcc: 2048, replyTo: 2048,
});
export function messageHeaderJSON(column = 'data') {
  const fields = Object.entries(MESSAGE_HEADER_LIMITS);
  const removed = ['body', 'html', 'translation', 'translationHTML', ...fields.map(([key]) => key)]
    .map(key => `'$.${key}'`).join(',');
  const bounded = fields.flatMap(([key, limit]) => [`'$.${key}'`,
    `substr(coalesce(json_extract(${column},'$.${key}'),''),1,${limit})`]).join(',');
  return `json_set(json_remove(${column},${removed}),${bounded})`;
}

export function messagePreviewColumns(column = 'data') {
  return `substr(json_extract(${column},'$.body'),1,8192) AS previewBody, `
    + `substr(json_extract(${column},'$.html'),1,32768) AS previewHTML`;
}

// Parse the query once and share the bounded header projection and snippet rule.
export function messageHeaderProjection(repo, { query = '', previews = true } = {}) {
  const firstTerm = parseSearch(query).terms[0];
  return row => {
    const message = repo.messageHeader(JSON.parse(row.data), {
      previews, source: { body: row.previewBody, html: row.previewHTML },
    });
    return firstTerm ? { ...message, searchSnippet: repo.searchIndex.snippet(message.id, firstTerm) } : message;
  };
}
