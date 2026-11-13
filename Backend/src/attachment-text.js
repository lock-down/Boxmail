import { textSlice } from './unicode.js';

export const MAX_EXTRACTED_TEXT = 200000;

export function extractedText(value) {
  const text = textSlice(value, 0, MAX_EXTRACTED_TEXT);
  return { text, textTruncated: text.length < value.length };
}
