import { ServiceError } from './validation.js';

const defaultSize = 14, defaultColor = '#232D3D';
const validSize = value => typeof value === 'number' && Number.isFinite(value) && value >= 8 && value <= 72;
const roundedSize = value => Math.round(value * 100) / 100;
const normalizedColor = value => value.toUpperCase() === defaultColor ? undefined : value.toUpperCase();

export function resolvedTextStyle(run) {
  return { fontSize: run.fontSize ?? defaultSize, color: run.color ?? defaultColor };
}

export function textStyle({ fontSize, color }) {
  if (fontSize != null && !validSize(fontSize)) throw new ServiceError('字号应为 8 至 72 pt');
  if (color != null && (typeof color !== 'string' || !/^#[\da-f]{6}$/i.test(color)))
    throw new ServiceError('文字颜色应为六位十六进制色值');
  const size = fontSize == null ? undefined : roundedSize(fontSize);
  const hex = color == null ? undefined : normalizedColor(color);
  return { ...(size != null && size !== defaultSize ? { fontSize: size } : {}), ...(hex ? { color: hex } : {}) };
}

export function styleAttribute({ fontSize, color }) {
  const styles = [fontSize != null ? `font-size:${fontSize}pt` : '', color ? `color:${color}` : ''].filter(Boolean);
  return styles.length ? ` style="${styles.join(';')}"` : '';
}

function cssColor(value) {
  const short = /^#([\da-f])([\da-f])([\da-f])$/i.exec(value);
  if (short) return '#' + short.slice(1).map(part => part + part).join('').toUpperCase();
  if (/^#[\da-f]{6}$/i.test(value)) return value.toUpperCase();
  const rgb = /^rgb\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*\)$/i.exec(value);
  if (rgb && rgb.slice(1).every(part => Number(part) <= 255))
    return '#' + rgb.slice(1).map(part => Number(part).toString(16).padStart(2, '0')).join('').toUpperCase();
  const named = { black: '#000000', white: '#FFFFFF', red: '#FF0000', green: '#008000', blue: '#0000FF',
    gray: '#808080', grey: '#808080', orange: '#FFA500', purple: '#800080' };
  return Object.hasOwn(named, value.toLowerCase()) ? named[value.toLowerCase()] : undefined;
}

// Import only literal, bounded style values; never retain arbitrary CSS in the editor.
export function styleFromHTML(name, attributes, inherited = {}) {
  let fontSize = inherited.fontSize, color = inherited.color;
  if (name === 'font') {
    if (/^[1-7]$/.test(attributes.size || '')) fontSize = [8, 10, 12, 14, 18, 24, 36][Number(attributes.size) - 1];
    if (attributes.color) color = cssColor(attributes.color.trim()) ?? color;
  }
  for (const declaration of (attributes.style || '').split(';')) {
    const colon = declaration.indexOf(':');
    if (colon < 0) continue;
    const property = declaration.slice(0, colon).trim().toLowerCase();
    const value = declaration.slice(colon + 1).trim().replace(/\s*!important\s*$/i, '');
    if (property === 'color') color = cssColor(value) ?? color;
    if (property === 'font-size') {
      const match = /^(\d+(?:\.\d+)?)\s*(pt|px)$/i.exec(value);
      const size = match ? Number(match[1]) * (match[2].toLowerCase() === 'px' ? 0.75 : 1) : NaN;
      if (validSize(size)) fontSize = roundedSize(size);
    }
  }
  return { fontSize, color };
}
