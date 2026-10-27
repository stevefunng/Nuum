import { testTempDir } from "../../../scripts/test-temp.mjs";
import assert from "node:assert/strict";
import { mkdir, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";
import { createSandbox } from "./create-sandbox.js";

async function fixture(permission: "always" | "ask" | "never" = "ask") {
  const home = await testTempDir(path.join(tmpdir(), "nuum-sandbox-home-"));
  const data = path.join(home, ".nuum");
  const agent = path.join(data, "agents", "a1");
  const scratch = path.join(agent, "scratch");
  const project = path.join(home, "project");
  const secret = path.join(data, "host-secrets.json");
  await Promise.all([mkdir(scratch, { recursive: true }), mkdir(project)]);
  await writeFile(secret, "secret");
  return {
    home, data, agent, scratch, project, secret,
    sandbox: createSandbox({ roots: { home, project, scratch, denied: [secret] }, permission })
  };
}

test("a symlink cannot escape the hard local execution root", async () => {
  const item = await fixture("always");
  const outside = await testTempDir(path.join(tmpdir(), "nuum-sandbox-outside-"));
  await symlink(outside, path.join(item.project, "escape"));
  const verdict = await item.sandbox.authorize("write-file", path.join(item.project, "escape", "x.txt"));
  assert.equal(verdict.decision, "deny");
  assert.match(verdict.reason ?? "", /outside the allowed local execution root/i);
});

test("host secrets are denied even with always permission", async () => {
  const item = await fixture("always");
  const verdict = await item.sandbox.authorize("read-file", item.secret);
  assert.equal(verdict.decision, "deny");
  assert.match(verdict.reason ?? "", /protected host-only/i);
});

test("a normal path outside the hard root is denied", async () => {
  const item = await fixture("always");
  const outside = await testTempDir(path.join(tmpdir(), "nuum-outside-"));
  assert.equal((await item.sandbox.authorize("read-file", path.join(outside, "x"))).decision, "deny");
});

test("scratch and project paths are pre-approved for reads and writes", async () => {
  const item = await fixture("never");
  for (const target of [path.join(item.scratch, "x"), path.join(item.project, "x")]) {
    assert.equal((await item.sandbox.authorize("read-file", target)).decision, "allow");
    assert.equal((await item.sandbox.authorize("write-file", target)).decision, "allow");
  }
});

test("Work knowledge roots are pre-approved for reads but reject writes", async () => {
  const item = await fixture("always");
  const knowledge = path.join(item.home, "knowledge");
  await mkdir(knowledge);
  const sandbox = createSandbox({
    roots: { home: item.home, project: null, scratch: item.scratch, denied: [], readOnly: [knowledge] },
    permission: "always"
  });
  assert.equal((await sandbox.authorize("read-file", path.join(knowledge, "guide.md"))).decision, "allow");
  assert.equal((await sandbox.authorize("list-directory", knowledge)).decision, "allow");
  assert.equal((await sandbox.authorize("write-file", path.join(knowledge, "guide.md"))).decision, "deny");
});

test("other agent stores are readable but never writable", async () => {
  const item = await fixture("always");
  const other = path.join(item.data, "agents", "a2", "profile.json");
  assert.equal((await item.sandbox.authorize("read-file", other)).decision, "allow");
  assert.equal((await item.sandbox.authorize("write-file", other)).decision, "deny");
  assert.equal((await item.sandbox.authorize("write-file", path.join(item.agent, "profile.json"))).decision, "deny");
});

test("an approval matches only the exact action and canonical path", async () => {
  const item = await fixture("ask");
  const requested = path.join(item.home, "notes", "one.txt");
  const approved = (await item.sandbox.authorize("read-file", requested)).target;
  const sandbox = createSandbox({
    roots: { home: item.home, project: null, scratch: item.scratch, denied: [item.secret] },
    permission: "ask",
    approvals: [{ action: "read-file", target: approved }]
  });
  assert.equal((await sandbox.authorize("read-file", approved)).decision, "allow");
  assert.equal((await sandbox.authorize("read-file", path.dirname(approved))).decision, "ask");
  assert.equal((await sandbox.authorize("write-file", approved)).decision, "ask");
});

test("a refused exact action is denied without another approval request", async () => {
  const item = await fixture("ask");
  const requested = path.join(item.home, "notes.txt");
  const target = (await item.sandbox.authorize("read-file", requested)).target;
  const sandbox = createSandbox({
    roots: { home: item.home, project: null, scratch: item.scratch, denied: [] },
    permission: "ask",
    refused: [{ action: "read-file", target }]
  });
  const verdict = await sandbox.authorize("read-file", requested);
  assert.equal(verdict.decision, "deny");
  assert.match(verdict.reason ?? "", /previously refused/i);
});

test("hard-denied commands stay denied under always permission", async () => {
  const item = await fixture("always");
  const verdict = await item.sandbox.authorize("run-command", "rm -rf /");
  assert.equal(verdict.decision, "deny");
  assert.equal(verdict.target, "rm");
});

test("command approvals use the first executable token", async () => {
  const item = await fixture("ask");
  const sandbox = createSandbox({
    roots: { home: item.home, project: item.project, scratch: item.scratch, denied: [] },
    permission: "ask",
    approvals: [{ action: "run-command", target: "git" }]
  });
  assert.equal((await sandbox.authorize("run-command", "FOO=1 /usr/bin/git status")).decision, "allow");
  assert.equal((await sandbox.authorize("run-command", "npm test")).decision, "ask");
});
