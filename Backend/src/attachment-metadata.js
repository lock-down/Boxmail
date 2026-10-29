import { accountReference } from './diagnostics.js';

export const UNKNOWN_CONTENT_TYPE = 'application/octet-stream';
const mimeType = /^[a-z0-9!#$%&'*+.^_`|~-]+\/[a-z0-9!#$%&'*+.^_`|~-]+(?:\s*;[^\u0000-\u001f\u007f]*)?$/i;

export function attachmentContentType(value) {
  if (typeof value !== 'string') return UNKNOWN_CONTENT_TYPE;
  const type = value.trim();
  return type.length <= 1024 && !/[\u0000-\u001f\u007f]/.test(type) && mimeType.test(type) ? type : UNKNOWN_CONTENT_TYPE;
}

// MIME parsers can return false for an empty Content-Type header. This optional
// metadata must never invalidate the attachment, its original bytes or a snapshot.
export function attachmentMetadata(value, { diagnostics, phase = 'read' } = {}) {
  const contentType = attachmentContentType(value.contentType);
  if (contentType === value.contentType) return value;
  const original = value.contentType;
  diagnostics?.recordCoalesced?.('data.attachment.repaired', {
    phase, field: '$.contentType', recordKind: 'attachment', record: accountReference(value.id),
    expectedType: 'string', actualType: original === null ? 'null' : Array.isArray(original) ? 'array'
      : original === undefined ? 'missing' : typeof original,
    action: 'defaulted',
  });
  return { ...value, contentType };
}
