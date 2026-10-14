import { ServiceError } from './validation.js';

const publicCodes = new Set([
  'EAUTH', 'ENOTFOUND', 'EAI_AGAIN', 'EDNS', 'ETIMEDOUT', 'ETIMEOUT',
  'ETLS', 'ESOCKET', 'ECONNREFUSED', 'ECONNRESET', 'ECONNECTION', 'EHOSTUNREACH',
  'ENETUNREACH', 'EPIPE', 'ERR_TLS_CERT_ALTNAME_INVALID', 'CERT_HAS_EXPIRED',
  'CERT_NOT_YET_VALID', 'DEPTH_ZERO_SELF_SIGNED_CERT', 'SELF_SIGNED_CERT_IN_CHAIN',
  'UNABLE_TO_VERIFY_LEAF_SIGNATURE', 'UNABLE_TO_GET_ISSUER_CERT_LOCALLY',
  'ERR_SSL_WRONG_VERSION_NUMBER',
]);
const publicStatuses = new Set(['NO', 'BAD', 'AUTHENTICATIONFAILED', 'UNAVAILABLE', 'PRIVACYREQUIRED']);

export function mailServiceError(error, protocol, account) {
  if (error instanceof ServiceError) return error;
  const code = publicCodes.has(error.originalCode) ? error.originalCode
    : publicCodes.has(error.code) ? error.code : '';
  const responseCode = Number(error.responseCode);
  const imapStatus = [error.serverResponseCode, error.responseStatus].find(value => publicStatuses.has(value));
  const status = protocol === 'SMTP' && Number.isInteger(responseCode) && responseCode >= 100 && responseCode <= 599
    ? String(responseCode) : imapStatus || '';
  const suffix = status || code ? `（${status || code}）` : '';
  const host = protocol === 'SMTP' ? account.smtpHost : account.imapHost;
  const isQQ = /^(imap|smtp)\.qq\.com$/i.test(host || '');
  const response = [error.responseText, error.response, error.message].filter(v => typeof v === 'string').join(' ');
  let message;
  if (error.authenticationFailed || code === 'EAUTH' || [530, 534, 535].includes(responseCode)) {
    message = isQQ
      ? `${protocol} 登录被 QQ 邮箱拒绝${suffix}。请检查完整邮箱地址和登录用户名，确认该邮箱的 IMAP/SMTP 服务已开启，并使用该邮箱生成且仍有效的授权码；账号异常、登录频率受限或服务暂时繁忙也可能导致此错误。`
      : `${protocol} 登录被服务器拒绝${suffix}。请检查完整登录用户名、授权码及邮箱的 IMAP/SMTP 服务状态。`;
  } else if (['ENOTFOUND', 'EAI_AGAIN', 'EDNS'].includes(code)) {
    message = `${protocol} 无法解析服务器地址${suffix}。请检查服务器地址和网络 DNS。`;
  } else if (['ETIMEDOUT', 'ETIMEOUT'].includes(code) || error.name === 'TimeoutError' || /timeout|timed out/i.test(response)) {
    message = `${protocol} 连接超时${suffix}。请检查网络、服务器地址及端口，稍后重试。`;
  } else if (/CERT|SELF_SIGNED|ISSUER|UNABLE_TO_VERIFY|ALTNAME/i.test(code)) {
    message = `${protocol} 服务器证书验证失败${suffix}。请检查服务器地址、系统时间及证书信任链。`;
  } else if (code === 'ETLS' || /SSL|TLS|WRONG_VERSION/i.test(code)) {
    message = `${protocol} SSL/TLS 握手失败${suffix}。请确认安全连接方式与服务器端口匹配。`;
  } else if (['ESOCKET', 'ECONNREFUSED', 'ECONNRESET', 'ECONNECTION', 'EHOSTUNREACH', 'ENETUNREACH', 'EPIPE'].includes(code)) {
    message = `${protocol} 无法建立连接或连接被中断${suffix}。请检查网络、服务器地址及端口。`;
  } else {
    message = `${protocol} 操作未完成${suffix}。请检查邮箱服务状态及服务器配置。`;
  }
  // Never return raw protocol responses: they may contain credentials or auth payloads.
  return new ServiceError(message, 502);
}
