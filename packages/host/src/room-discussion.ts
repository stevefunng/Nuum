/** Local Grokbot policy: three rotating rounds, ten public messages, two per turn. */
export const discussionLimits = { rounds: 3, messages: 10, perTurn: 2 } as const;
export function isPass(text: string): boolean { return !text.trim() || /^\(?\s*pass\s*\)?\.?$/i.test(text.trim()); }
export function orderSpeakers<T>(members: readonly T[], round: number): T[] {
  if (!members.length) return [];
  const offset = round % members.length;
  return [...members.slice(offset), ...members.slice(0, offset)];
}
function mentioned(text: string, handle: string): boolean {
  const needle = `@${handle}`;
  for (let at = text.indexOf(needle); at >= 0; at = text.indexOf(needle, at + 1)) {
    if (!/[a-z0-9]/.test(text[at - 1] ?? "") && !/[a-z0-9]/.test(text[at + needle.length] ?? "")) return true;
  }
  return false;
}
export function discussionResponders<T extends { id: string; name: string }>(members: readonly T[], messages: readonly { body: string; mentionedAgentIds: string[] }[], defaultAll = true): T[] {
  const ids = new Set<string>();
  for (const message of messages) {
    const text = message.body.toLowerCase();
    if (/(?:^|[^a-z0-9])@(everyone|all)\b/.test(text)) return [...members];
    for (const id of message.mentionedAgentIds) ids.add(id);
    if (message.mentionedAgentIds.length) continue;
    const aliases = new Map<string, string[]>();
    for (const member of members) {
      const name = member.name.trim().toLowerCase();
      for (const alias of new Set([name, name.replace(/\s+/g, ""), name.split(/\s+/)[0]!])) {
        if (alias) aliases.set(alias, [...(aliases.get(alias) ?? []), member.id]);
      }
    }
    for (const [alias, targets] of aliases) {
      if (!mentioned(text, alias)) continue;
      // Full-name mentions should not also be interpreted as an ambiguous first name.
      if (targets.length > 1) {
        const full = members.filter(member => targets.includes(member.id) && member.name.trim().toLowerCase() !== alias && mentioned(text, member.name.trim().toLowerCase()));
        if (full.length === 1) { ids.add(full[0]!.id); continue; }
        throw new Error(`Ambiguous @${alias}; use the member's full name or select a specific member`);
      }
      ids.add(targets[0]!);
    }
  }
  return !ids.size && defaultAll ? [...members] : members.filter(member => ids.has(member.id));
}

/** The room only owns this loop. Agent execution remains in AgentScheduler. */
export async function runDiscussion(deps: {
  current(): boolean;
  responders(): Promise<string[]>;
  runMember(agentId: string): Promise<{ messages: number; failed?: boolean }>;
}): Promise<void> {
  let total = 0;
  const failed = new Set<string>();
  for (let round = 0; round < discussionLimits.rounds && deps.current(); round++) {
    const order = orderSpeakers((await deps.responders()).filter(id => !failed.has(id)), round);
    let spoken = 0;
    for (const agentId of order) {
      if (!deps.current() || total >= discussionLimits.messages) return;
      const result = await deps.runMember(agentId);
      total += result.messages;
      spoken += result.messages;
      if (result.failed) failed.add(agentId);
    }
    if (!spoken) return;
  }
}
