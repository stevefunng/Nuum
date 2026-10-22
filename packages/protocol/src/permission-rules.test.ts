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
