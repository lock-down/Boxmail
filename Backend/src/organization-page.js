import { ServiceError } from './validation.js';

// Category counts cover the account; only the selected page's headers are decoded.
export function organizationPage(repo, { accountId = '', category = '', offset = 0, limit = 50 } = {}) {
  if (!Number.isSafeInteger(offset) || offset < 0 || !Number.isSafeInteger(limit) || limit < 1 || limit > 100
    || typeof category !== 'string' || category.length > 200)
    throw new ServiceError('整理列表分页参数无效');
  const scope = "kind='message' AND json_extract(data,'$.accountId')=? AND json_extract(data,'$.folder')='inbox'";
  const rawCategory = "json_extract(data,'$.category')";
  const categoryField = "coalesce(nullif(json_extract(data,'$.category'),''),'未分类')";
  // Match the indexed expressions before normalizing legacy empty categories.
  // Grouping/sorting payload rows would otherwise parse every large mail body.
  const categoryCounts = repo.db.prepare(`SELECT coalesce(nullif(category,''),'未分类') AS name, sum(n) AS count
    FROM (SELECT ${rawCategory} AS category, count(*) AS n FROM records INDEXED BY message_scope
      WHERE ${scope} GROUP BY ${rawCategory}) GROUP BY name ORDER BY name`).all(accountId);
  const accountTotal = categoryCounts.reduce((sum, row) => sum + row.count, 0);
  const total = category ? categoryCounts.find(row => row.name === category)?.count || 0 : accountTotal;
  offset = Math.min(offset, Math.max(0, Math.ceil(total / limit) - 1) * limit);
  const categoryClause = !category ? '' : category === '未分类'
    ? ` AND (${rawCategory}=? OR ${rawCategory}='' OR ${rawCategory} IS NULL)` : ` AND ${rawCategory}=?`;
  const ids = repo.db.prepare(`SELECT id FROM records INDEXED BY message_scope
    WHERE ${scope}${categoryClause} ORDER BY json_extract(data,'$.date') DESC,id LIMIT ? OFFSET ?`)
    .all(accountId, ...(category ? [category] : []), limit, offset).map(row => row.id);
  const headers = repo.db.prepare(`SELECT json_object('id',id,
    'accountId',json_extract(data,'$.accountId'),'folder','inbox',
    'sender',coalesce(json_extract(data,'$.sender'),''),'senderEmail',coalesce(json_extract(data,'$.senderEmail'),''),
    'subject',coalesce(json_extract(data,'$.subject'),''),'date',coalesce(json_extract(data,'$.date'),''),
    'category',${categoryField},'unread',json(CASE WHEN json_extract(data,'$.unread') THEN 'true' ELSE 'false' END),
    'starred',json(CASE WHEN json_extract(data,'$.starred') THEN 'true' ELSE 'false' END),
    'attachmentIds',json(coalesce(json_extract(data,'$.attachmentIds'),'[]')),
    'to','','cc','','body','','preview','','bodyLoaded',json('false')) AS data FROM records
    WHERE kind='message' AND id IN (SELECT value FROM json_each(?))`)
    .all(JSON.stringify(ids))
    .map(row => JSON.parse(row.data));
  const byID = new Map(headers.map(item => [item.id,item]));
  const items = ids.map(id => byID.get(id));
  return { items, total, offset, limit, accountTotal, categoryCounts };
}
