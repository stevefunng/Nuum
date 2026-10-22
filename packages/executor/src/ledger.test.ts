import assert from "node:assert/strict";
import { test } from "node:test";
import { ExecutionLedger } from "./ledger.js";

test("reconnecting queries existing execution without replay; mismatched reuse is refused", async () => {
  let calls = 0;
  const ledger = new ExecutionLedger(async () => { calls++; return { state: "finished", ok: true, output: "done" }; });
  const request = { id: "one", contextId: "context", name: "write", input: { path: "x", content: "a" } };
  ledger.submit(request);
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(ledger.submit(request), { state: "finished", ok: true, output: "done" });
  assert.equal(calls, 1);
  assert.throws(() => ledger.submit({ ...request, input: { path: "y" } }), /different/);
});

test("approval blocks execution and cancellation is terminal without executing", async () => {
  let calls = 0;
  const ledger = new ExecutionLedger(async () => { calls++; return { state: "finished", ok: true, output: "done" }; });
  const request = { id: "one", contextId: "context", name: "shell", input: { command: "echo hi" } };
  assert.equal(ledger.submit(request, { action: "run-command", target: "echo hi" }).state, "approval");
  ledger.refuse("one");
  assert.equal(ledger.submit(request).state, "finished");
  assert.equal(calls, 0);
});
