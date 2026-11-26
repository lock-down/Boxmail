import { conversationMembers } from './threads.js';

export function mailHistory(repo, messageId) {
  const thread = conversationMembers(repo, messageId);
  const memberIds = new Set(thread.members.map(member => member.id));
  const jobs = repo.db.prepare(`SELECT data FROM records
    WHERE kind='job' AND json_extract(data,'$.task') IN ('conversationSummary','conversationReply','reply')
    AND json_extract(data,'$.status')='completed'
    AND json_extract(data,'$.writingScope') IS NULL
    ORDER BY json_extract(data,'$.createdAt') DESC`).all()
    .map(row => JSON.parse(row.data))
    .filter(job => job.result && (job.task === 'reply' ? job.messageId === messageId :
      memberIds.has(job.messageId) || job.result.sourceMessages?.some(source => memberIds.has(source.id))));
  const summaries = jobs.filter(job => job.task === 'conversationSummary');
  const replies = jobs.filter(job => job.task !== 'conversationSummary' && typeof job.result.body === 'string' && job.result.body.trim());
  const turns = repo.list('assistantSession').flatMap(session => session.turns.filter(turn =>
    turn.scope.kind === 'message' && turn.scope.messageId === messageId ||
    turn.scope.kind === 'conversation' && memberIds.has(turn.scope.messageId) ||
    turn.sources.some(source => source.id === messageId) ||
    turn.citations.some(citation => citation.messageId === messageId)
  )).map(({ actions, ...turn }) => ({ ...turn, actions: [] }))
    .sort((a, b) => b.createdAt.localeCompare(a.createdAt));
  return { summaries, replies, turns };
}
