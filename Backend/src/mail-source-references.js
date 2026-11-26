// IMAP MOVE can replace a cache id while retaining the same original mail.
// Update links, while keeping user text and the content of saved answers intact.
export function remapMailSources(repo, previousId, messageId, attachmentIds = new Map()) {
  if (previousId === messageId && !attachmentIds.size) return;
  for (const item of repo.list('followUp').filter(item => item.messageId === previousId || item.replyMessageId === previousId))
    repo.put('followUp', { ...item, messageId: item.messageId === previousId ? messageId : item.messageId,
      replyMessageId: item.replyMessageId === previousId ? messageId : item.replyMessageId });
  for (const snooze of repo.list('snooze').filter(item => item.messageIds.includes(previousId)))
    repo.put('snooze', { ...snooze, messageIds: snooze.messageIds.map(id => id === previousId ? messageId : id) });
  if (previousId !== messageId) {
    const replaceId = id => id === previousId ? messageId : id;
    const jobs = repo.db.prepare(`SELECT data FROM records WHERE kind='job'
      AND json_extract(data,'$.task') IN ('conversationSummary', 'conversationReply')`).all();
    for (const row of jobs) {
      const job = JSON.parse(row.data);
      const result = job.result;
      if (!result || (result.replyMessageId !== previousId && !result.sourceIds?.includes(previousId)
        && !result.sourceMessages?.some(source => source.id === previousId))) continue;
      if (result.replyMessageId) result.replyMessageId = replaceId(result.replyMessageId);
      if (result.sourceIds) result.sourceIds = result.sourceIds.map(replaceId);
      for (const source of result.sourceMessages ?? []) source.id = replaceId(source.id);
      for (const item of [...(result.progress ?? []), ...(result.openItems ?? []), ...(result.conversationNextSteps ?? [])])
        item.messageIds = item.messageIds.map(replaceId);
      repo.put('job', job);
    }
  }
  for (const session of repo.list('assistantSession')) {
    let changed = false;
    const mapScope = scope => {
      if (scope.messageId === previousId) { scope.messageId = messageId; changed = true; }
      if (scope.attachmentIds?.some(id => attachmentIds.has(id))) {
        scope.attachmentIds = scope.attachmentIds.map(id => attachmentIds.get(id) || id); changed = true;
      }
    };
    mapScope(session.scope);
    for (const turn of session.turns) {
      mapScope(turn.scope);
      for (const source of turn.sources) if (source.id === previousId) { source.id = messageId; changed = true; }
      for (const citation of turn.citations) {
        if (citation.messageId === previousId) { citation.messageId = messageId; changed = true; }
        if (attachmentIds.has(citation.attachmentId)) { citation.attachmentId = attachmentIds.get(citation.attachmentId); changed = true; }
      }
      for (const action of turn.actions) if (action.messageIds.includes(previousId)) {
        action.messageIds = action.messageIds.map(id => id === previousId ? messageId : id);
        if (action.expected?.[previousId]) { action.expected[messageId] = action.expected[previousId]; delete action.expected[previousId]; }
        changed = true;
      }
    }
    if (changed) repo.put('assistantSession', session);
  }
  for (const run of repo.list('ruleRun')) {
    let changed = false;
    for (const item of run.items) if (item.id === previousId) {
      item.identity ||= previousId; item.id = messageId;
      for (const undo of item.undo || []) if (undo.id === previousId) undo.id = messageId;
      changed = true;
    }
    if (changed) repo.put('ruleRun', run);
  }
}
