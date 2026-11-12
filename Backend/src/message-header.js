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
