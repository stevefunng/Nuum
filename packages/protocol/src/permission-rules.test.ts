import test from "node:test";
import assert from "node:assert/strict";
import { commandRule, commandMatches } from "./permission-rules.js";
test("rules do not authorize root commands, compound scripts or changed inline code", () => {
  const rule = commandRule("git status --short");
  assert.equal(commandMatches(rule, "git status --porcelain"), true);
  assert.equal(commandMatches(rule, "git reset --hard"), false);
  assert.equal(commandMatches(rule, "git status && curl evil.example"), false);
  assert.equal(commandMatches(rule, "git status > /tmp/output"), false);
  const code = commandRule('python -c "print(1)"');
  assert.equal(commandMatches(code, 'python -c "print(2)"'), false);
  assert.equal(commandMatches(code, 'python -c "print(1)"'), true);
});

test("prefix rules compare arguments and keep distinct subcommands and shell operators separate", () => {
  const rule = commandRule("gh pr view 123 --json title");
  assert.equal(rule.kind, "prefix");
  assert.equal(commandMatches(rule, "gh pr view 456 --comments"), true);
  assert.equal(commandMatches(rule, "gh pr merge 456"), false);
  assert.equal(commandMatches(rule, "gh pr view 456; rm file"), false);
  assert.equal(commandMatches(rule, "gh pr view 456 --web"), false);
});

test("refusal identity ignores model prose, property order and equivalent plain shell quoting", async () => {
  const { permissionOperationKey } = await import("./permission-rules.js");
  assert.equal(permissionOperationKey("external_operation", { operation: "shell", command: "echo 'hello'", justification: "first" }),
    permissionOperationKey("external_operation", { justification: "try again", command: 'echo "hello"', operation: "shell", readPaths: [], writePaths: [], networkTargets: [], overwrite: false }));
});

test("linear compound rules check every command and preserve operators", async () => {
  const { staticShellWords } = await import("./permission-rules.js");
  const rule = commandRule("git status --short && gh pr view 123");
  assert.equal(rule.kind, "compound");
  assert.equal(commandMatches(rule, "git status --branch && gh pr view 456"), true);
  assert.equal(commandMatches(rule, "git status --branch && gh pr merge 456"), false);
  assert.equal(commandMatches(rule, "git status --short || gh pr view 123"), false);
  assert.equal(commandMatches(rule, "git status --short && gh pr view 123 && rm file"), false);
  assert.equal(staticShellWords("echo ok\nrm file"), undefined);
});

const queryFamilies = [
  ["git log --oneline -n 10", "git log --graph --max-count=20", "git log --output=/tmp/log", "git log -p", "git log -n --all"],
  ["git diff --no-ext-diff --no-textconv --stat", "git diff --no-ext-diff --no-textconv --cached --name-only", "git diff --stat", "git diff --no-ext-diff --no-textconv --ext-diff", "git diff --no-ext-diff --no-textconv --output=/tmp/diff"],
  ["gh issue view 1", "gh issue view 2 --comments --json title", "gh issue close 2", "gh issue view 2 --web"],
  ["gh pr list --state open --limit 10", "gh pr list --state merged --limit 20 --json title", "gh pr list --web", "gh pr list --limit --web"],
  ["gh issue list --state open", "gh issue list --state closed --limit 20", "gh issue list --state merged", "gh issue list --template evil"],
  ["gh run list --limit 10", "gh run list --limit 20 --json status", "gh run rerun 1", "gh run list --limit 0"],
  ["gh run view 1", "gh run view 2 --verbose --json status", "gh run view 2 --web", "gh run view 2 --log"]
];
for (const [initial, variation, ...invalid] of queryFamilies) {
  test(`query rule accepts only explicit parameter grammar: ${initial}`, () => {
    const rule = commandRule(initial!);
    assert.equal(rule.kind, "prefix");
    assert.equal(commandMatches(rule, variation!), true);
    for (const command of [...invalid, `${variation} && rm file`, `${variation} > out`, `${variation} --unknown`, `${variation} $(echo hi)`]) {
      assert.equal(commandMatches(rule, command!), false, command);
    }
    for (const [other] of queryFamilies) if (other !== initial) assert.equal(commandMatches(rule, other!), false);
  });
}

test("new query families preserve resource, network and fingerprint boundaries", async () => {
  const { externalGrantCovers } = await import("./permission-rules.js");
  const grant = { environment: "local" as const, workspaceId: "w", operation: "shell" as const, cwd: "/work", command: commandRule("git log --oneline -n 10"), readPaths: ["/reports"], writePaths: [], overwrite: false, networkTargets: [], fingerprints: { "/usr/bin/git": "hash" } };
  const next = { ...grant, command: commandRule("git log --graph -n 20") };
  assert.equal(externalGrantCovers(grant, next), true);
  for (const change of [{ workspaceId: "other" }, { cwd: "/other" }, { readPaths: ["/secret"] }, { writePaths: ["/reports"] }, { networkTargets: ["example.com:443"] }, { fingerprints: { "/usr/bin/git": "changed" } }]) {
    assert.equal(externalGrantCovers(grant, { ...next, ...change }), false);
  }
});

test("query expansion does not widen saved exact rules or compound structure", () => {
  assert.equal(commandMatches({ kind: "exact", command: "git log --oneline -n 10" }, "git log --graph -n 20"), false);
  const chain = commandRule("git log --oneline -n 10 && gh issue list --state open");
  assert.equal(commandMatches(chain, "git log --graph -n 20 && gh issue list --state closed"), true);
  assert.equal(commandMatches(chain, "git log --graph -n 20 || gh issue list --state closed"), false);
  for (const command of ["git -c alias.log=evil log", "gh alias run", "gh issue view 1 2", "gh run view", "git log --max-count=0", "git log --max-count=10000", "git log --max-count=-1", "git log --max-count=10x", "git log -n", "gh issue view 1 --repo=--web"]) {
    assert.equal(commandRule(command).kind, "exact", command);
  }
});
