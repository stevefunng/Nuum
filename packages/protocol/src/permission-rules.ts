import { z } from "zod";

export const NetworkTarget = z.string().regex(/^(?:[a-zA-Z0-9](?:[a-zA-Z0-9.-]*[a-zA-Z0-9])?):(?:443|80)$/, "Use an exact hostname and port 80 or 443");

const CommandAtom = z.discriminatedUnion("kind", [
  z.object({ kind: z.literal("exact"), command: z.string() }),
  z.object({ kind: z.literal("prefix"), argv: z.array(z.string()) })
]);
export const CommandRule = z.union([CommandAtom, z.object({ kind: z.literal("compound"), commands: z.array(CommandAtom), operators: z.array(z.string()) })]);
export type CommandRule = z.infer<typeof CommandRule>;
// Explicit option grammars: unknown flags, extra positionals and missing values fail closed.
interface QueryGrammar {
  flags: readonly string[];
  values?: Record<string, RegExp>;
  positional?: RegExp;
  required?: readonly string[];
}
const positiveCount = /^[1-9][0-9]{0,3}$/;
const ghValues = { "--json": /^[a-zA-Z]+(?:,[a-zA-Z]+)*$/, "--repo": /^[a-zA-Z0-9_.-]+\/[a-zA-Z0-9_.-]+$/ };
const queryGrammars: Record<string, QueryGrammar> = {
  "git log": { flags: ["--oneline", "--graph", "--all", "--reverse", "--no-merges", "--first-parent", "--no-decorate"], values: { "-n": positiveCount, "--max-count": positiveCount } },
  "git diff": { flags: ["--no-ext-diff", "--no-textconv", "--stat", "--name-only", "--name-status", "--numstat", "--shortstat", "--cached", "--staged", "--check"], required: ["--no-ext-diff", "--no-textconv"] },
  "gh issue view": { flags: ["--comments"], values: ghValues, positional: /^[1-9][0-9]*$/ },
  "gh pr list": { flags: [], values: { ...ghValues, "--limit": positiveCount, "--state": /^(open|closed|merged|all)$/ } },
  "gh issue list": { flags: [], values: { ...ghValues, "--limit": positiveCount, "--state": /^(open|closed|all)$/ } },
  "gh run list": { flags: [], values: { ...ghValues, "--limit": positiveCount } },
  "gh run view": { flags: ["--verbose"], values: ghValues, positional: /^[1-9][0-9]*$/ }
};
function queryArgumentsMatch(args: string[], grammar: QueryGrammar): boolean {
  let positionals = 0;
  for (let i = 0; i < args.length; i++) {
    const arg = args[i]!;
    if (grammar.flags.includes(arg)) continue;
    const equals = arg.indexOf("=");
    const option = equals > 0 ? arg.slice(0, equals) : arg;
    const pattern = grammar.values?.[option];
    if (pattern) {
      if (!pattern.test(equals > 0 ? arg.slice(equals + 1) : args[++i] ?? "")) return false;
      continue;
    }
    if (grammar.positional?.test(arg) && positionals++ === 0) continue;
    return false;
  }
  return (!grammar.positional || positionals === 1) && (grammar.required ?? []).every(flag => args.includes(flag));
}
// Recognize only argument grammars whose prefix can be reused without swallowing shell syntax.
function reusablePrefix(command: string): string[] | undefined {
  const words = staticShellWords(command);
  if (!words) return;
  const program = words[0]!.split("/").at(-1);
  const prefix = program === "git" ? [program, words[1]] : [program, words[1], words[2]];
  const grammar = queryGrammars[prefix.join(" ")];
  if (grammar && queryArgumentsMatch(words.slice(prefix.length), grammar)) return prefix as string[];
  if (program === "git" && words[1] === "status" && words.slice(2).every(word => /^(--short|--porcelain(?:=v[12])?|--branch|-s|-b)$/.test(word))) return ["git", "status"];
  if (program === "gh" && words[1] === "pr" && words[2] === "view") {
    const args = words.slice(3);
    for (let i = 0; i < args.length; i++) {
      const value = args[i]!;
      if (/^\d+$/.test(value) || value === "--comments") continue;
      if (value === "--json" && /^[a-zA-Z,]+$/.test(args[++i] ?? "")) continue;
      if (value === "--repo" && /^[a-zA-Z0-9_.-]+\/[a-zA-Z0-9_.-]+$/.test(args[++i] ?? "")) continue;
      return;
    }
    return ["gh", "pr", "view"];
  }
}
function atomRule(command: string): z.infer<typeof CommandAtom> {
  const argv = reusablePrefix(command);
  return argv ? { kind: "prefix", argv } : { kind: "exact", command };
}
export function commandRule(command: string): CommandRule {
  const chain = splitShellCommands(command);
  return chain && chain.commands.length > 1
    ? { kind: "compound", commands: chain.commands.map(atomRule), operators: chain.operators }
    : atomRule(command);
}
export function commandMatches(rule: CommandRule, command: string): boolean {
  if (rule.kind === "compound") {
    const chain = splitShellCommands(command);
    return Boolean(chain && JSON.stringify(chain.operators) === JSON.stringify(rule.operators) && chain.commands.length === rule.commands.length && chain.commands.every((part, i) => commandMatches(rule.commands[i]!, part)));
  }
  return rule.kind === "exact" ? rule.command === command : JSON.stringify(reusablePrefix(command)) === JSON.stringify(rule.argv);
}
export const ExternalOperation = z.object({
  operation: z.enum(["read", "import", "export", "shell"]),
  justification: z.string().trim().min(1).max(1000),
  source: z.string().optional(), destination: z.string().optional(),
  resourceRoot: z.string().optional(),
  command: z.string().min(1).optional(), cwd: z.string().optional(),
  readPaths: z.array(z.string()).max(16).default([]), writePaths: z.array(z.string()).max(16).default([]),
  networkTargets: z.array(NetworkTarget).max(16).default([]),
  overwrite: z.boolean().default(false)
}).strict();
export type ExternalOperation = z.infer<typeof ExternalOperation>;
export const ExternalGrant = z.object({
  environment: z.literal("local"), workspaceId: z.string(), scope: z.enum(["file", "directory"]).optional(),
  operation: z.enum(["read", "import", "export", "shell"]),
  source: z.string().optional(), destination: z.string().optional(),
  cwd: z.string().optional(), command: CommandRule.optional(),
  readPaths: z.array(z.string()), writePaths: z.array(z.string()), overwrite: z.boolean(),
  // Fingerprint executable/script inputs before reusing shell permissions.
  networkTargets: z.array(NetworkTarget).optional(),
  rememberable: z.boolean().optional(),
  fingerprints: z.record(z.string()).default({})
});
export type ExternalGrant = z.infer<typeof ExternalGrant>;
export function externalGrantCovers(grant: ExternalGrant, wanted: ExternalGrant): boolean {
  if (grant.environment !== wanted.environment || grant.workspaceId !== wanted.workspaceId || grant.operation !== wanted.operation) return false;
  const contains = (root: string | undefined, value: string | undefined) => root === value || Boolean(root && value?.startsWith(root + "/"));
  if (grant.scope === "directory") {
    if (!contains(grant.source, wanted.source) || !contains(grant.destination, wanted.destination)) return false;
  } else if (wanted.scope === "directory" || grant.source !== wanted.source || grant.destination !== wanted.destination) return false;
  if (!(wanted.networkTargets ?? []).every(target => (grant.networkTargets ?? []).includes(target))) return false;
  if (grant.cwd !== wanted.cwd || grant.overwrite !== wanted.overwrite) return false;
  if (JSON.stringify(grant.readPaths) !== JSON.stringify(wanted.readPaths) || JSON.stringify(grant.writePaths) !== JSON.stringify(wanted.writePaths) || JSON.stringify(grant.fingerprints) !== JSON.stringify(wanted.fingerprints)) return false;
  return JSON.stringify(grant.command) === JSON.stringify(wanted.command);
}

/** Request identity excludes model prose and sorts object keys; changing a reason cannot defeat refusal. */
export function permissionOperationKey(name: string, input: Record<string, unknown>): string {
  const stable = (value: unknown): unknown => Array.isArray(value) ? value.map(stable) : value && typeof value === "object"
    ? Object.fromEntries(Object.entries(value).filter(([key]) => key !== "justification").sort(([a], [b]) => a.localeCompare(b)).map(([key, item]) => [key, stable(item)])) : value;
  const normalized = { ...input };
  if (name === "external_operation") {
    const parsed = ExternalOperation.safeParse(input);
    if (parsed.success) Object.assign(normalized, parsed.data);
  }
  if (typeof normalized.command === "string") normalized.command = staticShellWords(normalized.command) ?? normalized.command.trim();
  for (const key of ["readPaths", "writePaths"]) if (Array.isArray(normalized[key])) normalized[key] = [...normalized[key] as string[]].sort();
  return JSON.stringify([name, stable(normalized)]);
}

/** Conservative POSIX words only. No expansion, redirection, pipelines or control syntax. */
export function staticShellWords(command: string): string[] | undefined {
  const words: string[] = []; let word = "", quoted: string | undefined, started = false;
  for (let i = 0; i < command.length; i++) {
    const ch = command[i]!;
    if (quoted) {
      if (ch === quoted) { quoted = undefined; continue; }
      if (quoted === '"' && /[$`\\]/.test(ch)) return;
      word += ch; continue;
    }
    if (ch === "'" || ch === '"') { quoted = ch; started = true; continue; }
    if (ch === "\n" || ch === "\r") return;
    if (/\s/.test(ch)) { if (started) { words.push(word); word = ""; started = false; } continue; }
    if (/[;&|<>$`\\*?(){}\[\]~]/.test(ch)) return;
    word += ch; started = true;
  }
  if (quoted) return;
  if (started) words.push(word);
  return words.length ? words : undefined;
}

/** Linear shell chains only; preserve operators and reject dynamic/control syntax. */
export function splitShellCommands(command: string): { commands: string[]; operators: string[] } | undefined {
  const commands: string[] = [], operators: string[] = [];
  let quote: string | undefined, start = 0;
  for (let i = 0; i < command.length; i++) {
    const ch = command[i]!;
    if (quote) { if (ch === quote) quote = undefined; else if (quote === '"' && /[$`\\]/.test(ch)) return; continue; }
    if (ch === "'" || ch === '"') { quote = ch; continue; }
    if (ch === "&" && command[i + 1] !== "&") return;
    if (ch === ";" || ch === "|" || ch === "&") {
      const part = command.slice(start, i).trim();
      if (!staticShellWords(part)) return;
      commands.push(part);
      const doubled = (ch === "&" || ch === "|") && command[i + 1] === ch;
      operators.push(doubled ? ch + ch : ch);
      if (doubled) i++;
      start = i + 1;
    }
  }
  const tail = command.slice(start).trim();
  if (quote || !staticShellWords(tail)) return;
  commands.push(tail);
  return { commands, operators };
}
