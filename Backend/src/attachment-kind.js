import { existsSync, readFileSync } from 'node:fs';
import path from 'node:path';

// One shared table with the Swift client. The packaged copy wins in the App;
// the source copy keeps backend-only tests working without a build step.
const packaged = new URL('../Resources/AttachmentKinds.json', import.meta.url);
const source = new URL('../../Sources/BoxmailCore/Resources/AttachmentKinds.json', import.meta.url);
const formats = JSON.parse(readFileSync(existsSync(packaged) ? packaged : source, 'utf8')).formats;

const dotted = entry => entry.extensions.map(extension => `.${extension}`);

export const extensions = Object.freeze(Object.fromEntries(
  formats.flatMap(entry => entry.extensions.map(extension => [extension, entry.kind]))));
const mimeKinds = Object.freeze(Object.fromEntries(
  formats.flatMap(entry => entry.mimes.map(mime => [mime, entry.kind]))));

export const archiveFormats = Object.freeze(Object.fromEntries(
  formats.filter(entry => entry.archive)
    .flatMap(entry => dotted(entry).map(extension => [extension, entry.mimes[0]]))));
export const textExtensions = new Set(
  formats.filter(entry => entry.text).flatMap(dotted));
export const imageMimes = new Set(
  formats.filter(entry => entry.kind === 'image').flatMap(entry => entry.mimes));
export const imageExtensions = Object.freeze(Object.fromEntries(
  formats.filter(entry => entry.kind === 'image')
    .flatMap(entry => dotted(entry).map(extension => [extension, entry.mimes[0]]))));
export const presentationExtensions = new Set(
  formats.filter(entry => entry.kind === 'presentation').flatMap(dotted));
export const presentationMimes = Object.freeze(
  formats.filter(entry => entry.kind === 'presentation').reduce((map, entry) => {
    for (const mime of entry.mimes) map[mime] ??= `.${entry.extensions[0]}`;
    return map;
  }, {}));
export const modelExtensions = Object.freeze(
  Object.fromEntries([['.pdf', null], ...Object.entries(imageExtensions)]));

export function attachmentKind(name, mime) {
  return extensions[path.extname(name || '').slice(1).toLowerCase()]
    || mimeKinds[(mime || '').split(';')[0].trim().toLowerCase()] || 'other';
}
