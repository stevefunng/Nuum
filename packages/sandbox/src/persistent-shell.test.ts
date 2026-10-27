import { testTempDir } from "../../../scripts/test-temp.mjs";
import assert from "node:assert/strict";
import { mkdir, readFile, realpath } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { test, type TestContext } from "node:test";
import { createSandbox, disposeAllShells } from "./index.js";

async function fixture(t: TestContext) {
  const home = await testTempDir(path.join(tmpdir(), "nuum-shell-"));
  const projectPath = path.join(home, "project");
  const agent = path.join(home, "data", "agents", "a1");
  const scratch = path.join(agent, "scratch");
  const terminals = path.join(agent, "terminals");
  await Promise.all([mkdir(projectPath, { recursive: true }), mkdir(scratch, { recursive: true })]);
  const project = await realpath(projectPath);
  t.after(() => disposeAllShells());
  const make = () => createSandbox({
    roots: { home, project, scratch, terminals, denied: [] },
    permission: "always"
  });
  return { home, project, scratch, terminals, make };
}

test("one agent reuses cwd and environment across sandbox instances", async (t) => {
  const item = await fixture(t);
  const first = item.make();
  const changed = await first.shell({
    command: "mkdir -p child && export NUUM_SHELL_VALUE=kept && cd child && printf changed",
    blockUntilMs: 2_000
  });
  assert.equal(changed.exitCode, 0);
  assert.equal(changed.background, false);

  // 每个 turn 都会新建 LocalSandbox；terminals 根相同才是同一个 agent shell。
  const second = item.make();
  const observed = await second.shell({
    command: "printf '%s|%s' \"$NUUM_SHELL_VALUE\" \"$PWD\"",
    blockUntilMs: 2_000
  });
  assert.match(observed.tail, new RegExp(`kept\\|${escapeRegex(path.join(item.project, "child"))}$`));
});

test("working_directory is command-local and a missing directory falls back with a notice", async (t) => {
  const item = await fixture(t);
  const other = path.join(item.project, "other");
  await mkdir(other);
  const sandbox = item.make();
  const inOther = await sandbox.shell({ command: "pwd", workingDirectory: other, blockUntilMs: 2_000 });
  assert.equal(inOther.cwd, other);
  assert.match(inOther.tail, new RegExp(`${escapeRegex(other)}$`));

  const after = await sandbox.shell({ command: "pwd", blockUntilMs: 2_000 });
  assert.match(after.tail, new RegExp(`${escapeRegex(item.project)}$`));

  const missing = await sandbox.shell({
    command: "pwd",
    workingDirectory: path.join(item.project, "missing"),
    blockUntilMs: 2_000
  });
  assert.match(missing.notice ?? "", /does not exist.*fell back/si);
  assert.match(missing.tail, new RegExp(`${escapeRegex(item.project)}$`));
});

test("block timeout returns a background shell id and inspection sees the eventual footer", async (t) => {
  const item = await fixture(t);
  const sandbox = item.make();
  const started = await sandbox.shell({
    command: "printf begin; sleep 0.15; printf end",
    blockUntilMs: 5
  });
  assert.equal(started.background, true);
  assert.equal(started.exitCode, null);
  assert.match(started.shellId, /^[0-9a-f-]{36}$/);
  assert.equal(started.path, path.join(item.terminals, `${started.shellId}.txt`));
  assert.match(
    await readFile(started.path, "utf8"),
    /pid: \d+\ncwd: .*\nrunning_for_ms: 0\nstarted_at_ms: \d+\n---/
  );

  let completed = started;
  for (let i = 0; i < 100 && completed.exitCode === null; i += 1) {
    await new Promise((resolve) => setTimeout(resolve, 5));
    completed = await sandbox.shell({ shellId: started.shellId });
  }
  assert.equal(completed.background, false);
  assert.equal(completed.exitCode, 0);
  assert.match(completed.tail, /beginend$/);
  assert.match(await readFile(started.path, "utf8"), /---\nexit_code: 0\n$/);
});

test("disposing a shell kills its process group and seals the active output", async (t) => {
  const item = await fixture(t);
  const sandbox = item.make();
  const started = await sandbox.shell({
    command: "sleep 30 & printf '%s' $!; wait",
    blockUntilMs: 20
  });
  assert.equal(started.background, true);
  let inspected = started;
  for (let i = 0; i < 100 && !/\d+/.test(inspected.tail); i += 1) {
    await new Promise((resolve) => setTimeout(resolve, 5));
    inspected = await sandbox.shell({ shellId: started.shellId });
  }
  const childPid = Number(inspected.tail.match(/\d+/)?.[0]);
  assert.equal(Number.isInteger(childPid), true);

  await sandbox.disposeShell();
  await assert.rejects(
    async () => process.kill(childPid, 0),
    (error: NodeJS.ErrnoException) => error.code === "ESRCH"
  );
  assert.match(await readFile(started.path, "utf8"), /exit_code: 130/);

  const replacement = item.make();
  const restarted = await replacement.shell({ command: "printf restarted", blockUntilMs: 2_000 });
  assert.equal(restarted.exitCode, 0);
  assert.equal(restarted.tail, "restarted");
});

function escapeRegex(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}
