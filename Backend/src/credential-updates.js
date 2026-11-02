import { ServiceError } from './validation.js';

// Ordinary settings saves can publish only fresh, scoped credential references.
export function credentialUpdates(input, allowed) {
  if (input === undefined) return {};
  const valid = value => typeof value === 'string'
    && /^configuration-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
  if (!input || typeof input !== 'object' || Array.isArray(input)
    || Object.entries(input).some(([key, value]) => !allowed.includes(key) || !valid(value))
    || new Set(Object.values(input)).size !== Object.keys(input).length)
    throw new ServiceError('凭证保存状态无效，请重新保存设置');
  return input;
}
