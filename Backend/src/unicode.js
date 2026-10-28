// JavaScript offsets count UTF-16 units. Keep display/extraction limits without
// leaving half a surrogate pair for Foundation's stricter JSON decoder.
export function textSlice(text, start = 0, end = text.length) {
  const offset = value => Math.max(0, Math.min(text.length, value < 0 ? text.length + value : value));
  let first = offset(start), last = offset(end);
  const high = value => value >= 0xD800 && value <= 0xDBFF;
  const low = value => value >= 0xDC00 && value <= 0xDFFF;
  if (low(text.charCodeAt(first)) && high(text.charCodeAt(first - 1))) first++;
  if (high(text.charCodeAt(last - 1)) && low(text.charCodeAt(last))) last--;
  return text.slice(first, Math.max(first, last)).toWellFormed();
}

// JSON.stringify accepts lone surrogates and emits escapes that Swift rejects.
// Repair string values at both persistence and wire boundaries; old records can
// be read without rewriting or deleting their original bodies and attachments.
export function unicodeJSON(value) {
  return JSON.stringify(value, (_key, item) => typeof item === 'string' ? item.toWellFormed() : item);
}
