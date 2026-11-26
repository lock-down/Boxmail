import { ServiceError } from './validation.js';

const filters = {
  all: '1',
  mine: "state = 'mine' AND NOT snoozed",
  waiting: "state = 'waiting' AND NOT snoozed",
  snoozed: "state <> 'completed' AND snoozed",
  completed: "state = 'completed'",
  due: 'isDue',
  removed: '0',
};

// Page source messages after matching and filtering their actions. The query
// returns only the selected page's summaries and item details, never mail bodies.
export function checklistPage(repo, { accountId, filter = 'all', offset = 0, limit = 50, followUpId } = {}) {
  if (!Object.hasOwn(filters, filter) || !Number.isSafeInteger(offset) || offset < 0
    || !Number.isSafeInteger(limit) || limit < 1 || limit > 100) throw new ServiceError('清单筛选或分页参数无效');

  const scope = accountId == null ? '' : " AND json_extract(data,'$.accountId') = :accountId";
  const records = repo.db.prepare(`WITH
    summaries AS MATERIALIZED (
      SELECT id AS messageId, json_extract(data,'$.accountId') AS accountId,
        json_extract(data,'$.summary') AS summary,
        coalesce(json_extract(data,'$.summaryHidden'), 0) AS hidden
      FROM records WHERE kind = 'message' ${scope}
        AND json_type(data,'$.summary') = 'object' AND json_extract(data,'$.folder') <> 'trash'
    ),
    suggestions AS MATERIALIZED (
      SELECT s.messageId, s.accountId, s.hidden, json_extract(todo.value,'$.id') AS todoId, todo.value AS todo, todo.key AS ordinal,
        'todo:' || json_extract(todo.value,'$.title') || char(31) || json_extract(todo.value,'$.due') AS sourceKey
      FROM summaries s, json_each(s.summary,'$.todos') todo
    ),
    follow_ups AS MATERIALIZED (
      SELECT id, json_extract(data,'$.accountId') AS accountId,
        json_extract(data,'$.messageId') AS messageId, data
      FROM records WHERE kind = 'followUp' ${scope}
    ),
    linked AS MATERIALIZED (
      SELECT f.*, coalesce(json_extract(f.data,'$.todoId'), (
        SELECT t.todoId FROM suggestions t WHERE t.accountId = f.accountId AND t.messageId = f.messageId
          AND (json_extract(f.data,'$.sourceKey') = t.sourceKey
            OR (json_extract(f.data,'$.sourceKey') GLOB 'rule:*'
              AND substr(json_extract(f.data,'$.sourceKey'), -length(t.todoId)-1) = ':' || t.todoId))
        ORDER BY t.todoId LIMIT 1
      )) AS todoId
      FROM follow_ups f
    ),
    primary_actions AS (
      SELECT *, row_number() OVER (PARTITION BY accountId, messageId, coalesce(todoId,id)
        ORDER BY json_extract(data,'$.todoId') IS NOT NULL DESC, json_extract(data,'$.updatedAt') DESC, id) AS preference
      FROM linked
    ),
    actions AS (
      SELECT messageId, accountId, id, todoId, NULL AS todo, data AS followUp,
        json_extract(data,'$.state') AS state, json_extract(data,'$.createdAt') AS createdAt,
        (SELECT t.ordinal FROM suggestions t WHERE t.accountId = f.accountId AND t.messageId = f.messageId
          AND t.todoId = f.todoId LIMIT 1) AS ordinal,
        coalesce(julianday(json_extract(data,'$.snoozedUntil')) > julianday('now'), 0) AS snoozed,
        coalesce(json_extract(data,'$.state') <> 'completed'
          AND NOT json_extract(data,'$.reminderCancelled')
          AND julianday(coalesce(json_extract(data,'$.snoozedUntil'),json_extract(data,'$.dueAt'))) <= julianday('now'), 0) AS isDue
      FROM primary_actions f WHERE f.preference = 1 AND NOT coalesce(json_extract(data,'$.dismissed'), 0)
        AND (coalesce(json_extract(data,'$.collected'), 1) OR EXISTS (
          SELECT 1 FROM summaries s WHERE s.accountId = f.accountId AND s.messageId = f.messageId AND NOT s.hidden
        ))
      UNION ALL
      SELECT t.messageId, t.accountId, t.todoId, t.todoId, t.todo, NULL,
        CASE WHEN json_extract(t.todo,'$.done') THEN 'completed' ELSE 'mine' END, '', t.ordinal, 0, 0
      FROM suggestions t WHERE NOT t.hidden AND NOT EXISTS (
        SELECT 1 FROM linked f WHERE f.accountId = t.accountId AND f.messageId = t.messageId AND f.todoId = t.todoId
      )
    ),
    filtered AS MATERIALIZED (SELECT * FROM actions WHERE ${filters[filter]}),
    members AS (
      SELECT accountId, messageId, max(isDue) AS isDue, min(nullif(createdAt,'')) AS createdAt
      FROM (
        SELECT accountId, messageId, 0 AS isDue, '' AS createdAt
        FROM summaries WHERE (:filter = 'all' AND NOT hidden) OR (:filter = 'removed' AND hidden)
        UNION ALL
        SELECT accountId, messageId, isDue, createdAt FROM filtered
      ) GROUP BY accountId, messageId
    ),
    sources AS (
      SELECT s.accountId, s.messageId, s.isDue,
        coalesce(json_extract(m.data,'$.date'), s.createdAt, '') AS date,
        coalesce(json_extract(m.data,'$.subject'), (
          SELECT json_extract(f.data,'$.subject') FROM follow_ups f
          WHERE f.accountId = s.accountId AND f.messageId = s.messageId ORDER BY f.id LIMIT 1
        ), '') AS subject,
        coalesce(json_extract(m.data,'$.sender'), '') AS sender, m.id IS NOT NULL AS hasSource
      FROM members s LEFT JOIN records m ON m.kind = 'message' AND m.id = s.messageId
        AND json_extract(m.data,'$.accountId') = s.accountId
    ),
    ranked AS MATERIALIZED (
      SELECT *, row_number() OVER (ORDER BY CASE WHEN :filter = 'mine' THEN isDue ELSE 0 END DESC,
        date DESC, accountId, messageId) - 1 AS position
      FROM sources
    ),
    target AS (
      SELECT f.id, f.accountId, f.messageId FROM linked old JOIN filtered f
        ON f.accountId = old.accountId AND f.messageId = old.messageId
        AND (f.id = old.id OR f.todoId = old.todoId)
      WHERE old.id = :followUpId AND f.followUp IS NOT NULL
    ),
    bounds AS (
      SELECT count(*) AS total, max(CASE WHEN EXISTS (
        SELECT 1 FROM target t WHERE t.accountId = r.accountId AND t.messageId = r.messageId
      ) THEN position END) AS target FROM ranked r
    ),
    page AS (
      SELECT total, target, CASE WHEN target IS NOT NULL THEN (target / :limit) * :limit
        ELSE min(:offset, max(0, (total - 1) / :limit) * :limit) END AS offset
      FROM bounds
    )
    SELECT p.total, p.offset, (SELECT id FROM target) AS targetFollowUpId,
      r.accountId, r.messageId, r.subject, r.sender, r.date, r.hasSource,
      s.summary, coalesce(s.hidden, 0) AS summaryHidden,
      (SELECT json_group_array(json_object('id',coalesce(f.todoId,f.id),'todoId',f.todoId,'todo',json(f.todo),'followUp',json(f.followUp)))
        FROM (SELECT * FROM filtered WHERE accountId = r.accountId AND messageId = r.messageId
          ORDER BY ordinal NULLS LAST, createdAt, id) f) AS items
    FROM page p LEFT JOIN ranked r ON r.position >= p.offset AND r.position < p.offset + :limit
    LEFT JOIN summaries s ON s.accountId = r.accountId AND s.messageId = r.messageId
      AND (NOT s.hidden OR :filter = 'removed')
    ORDER BY r.position`).all({ ...(accountId == null ? {} : { accountId }), filter, followUpId: followUpId ?? null, offset, limit });

  const [{ total, offset: pageOffset, targetFollowUpId }] = records;
  return { total, offset: pageOffset, limit, targetFollowUpId,
    rows: records.filter(row => row.messageId != null).map(row => ({
      accountId: row.accountId, messageId: row.messageId, subject: row.subject, sender: row.sender, date: row.date,
      hasSource: !!row.hasSource, summary: row.summary && JSON.parse(row.summary), summaryHidden: !!row.summaryHidden,
      items: JSON.parse(row.items),
    })) };
}
