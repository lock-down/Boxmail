import { randomUUID } from 'node:crypto';

// Imported data cannot authorize reusing a local secret at a different endpoint.
// Both configuration imports and backup restores use this same trust policy.
export function credentialBindings(settings, accounts, localSettings, localAccounts) {
  const references = {}, reset = [];
  const providers = ai => ai?.providers ?? [{ id: 'default', baseURL: ai?.baseURL, apiProtocol: ai?.apiProtocol || 'openai-responses' }];
  const localProviders = new Map(providers(localSettings?.ai).map(p => [p.id, p]));
  const bind = (logical, trusted) => {
    if (trusted) {
      const reference = localSettings?.credentialReferences?.[logical];
      if (typeof reference === 'string' && reference) references[logical] = reference;
    } else {
      references[logical] = `configuration-${randomUUID()}`;
      reset.push(logical);
    }
  };
  for (const provider of providers(settings.ai)) {
    const local = localProviders.get(provider.id);
    const endpoint = value => { try { return new URL(value).href.replace(/\/+$/, ''); } catch { return null; } };
    bind(provider.id === 'default' ? 'ai-key' : `ai-provider-${provider.id}`,
      !!local && endpoint(local.baseURL) === endpoint(provider.baseURL)
        && (local.apiProtocol || 'openai-responses') === (provider.apiProtocol || 'openai-responses'));
  }
  for (const account of accounts) {
    const local = localAccounts.find(a => a.id === account.id);
    bind(`mail-${account.id}`, !!local && ['email', 'username', 'imapHost', 'imapPort', 'imapTLS', 'smtpHost', 'smtpPort', 'smtpTLS', 'isDemo']
      .every(field => field === 'email'
        ? account[field]?.trim().toLowerCase() === local[field]?.trim().toLowerCase() : account[field] === local[field]));
  }
  return { references, reset };
}
