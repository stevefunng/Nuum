import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import { test } from "node:test";
import { JsonRpcPeer, type ByteDuplex } from "./transport.js";

function pipe(): { a: ByteDuplex; b: ByteDuplex } {
  const left = new EventEmitter();
  const right = new EventEmitter();
  const make = (read: EventEmitter, write: EventEmitter): ByteDuplex => ({
    write(line) {
      queueMicrotask(() => write.emit("line", line));
    },
    onLine(listener) {
      read.on("line", listener);
      return () => {
        read.off("line", listener);
      };
    }
  });
  return { a: make(left, right), b: make(right, left) };
}

test("json-rpc request/response and events", async () => {
  const { a, b } = pipe();
  const client = new JsonRpcPeer(a);
  const server = new JsonRpcPeer(b);
  server.setHandler(async (method, params) => {
    if (method === "sys.ping") return { ok: true, echo: params };
    throw new Error("unknown");
  });
  const seen: string[] = [];
  client.onEvent((method) => seen.push(method));
  const result = await client.request("sys.ping", { n: 1 });
  assert.deepEqual(result, { ok: true, echo: { n: 1 } });
  server.notify("session.updated", { id: "s1" });
  await new Promise((resolve) => setTimeout(resolve, 10));
  assert.deepEqual(seen, ["session.updated"]);
});

test("closing RPC rejects outstanding and future requests", async () => {
  const peer = new JsonRpcPeer({ write() {}, onLine: () => () => {} });
  const pending = peer.request("waiting");
  const rejected = assert.rejects(pending, /closed/);
  peer.close(new Error("closed"));
  await rejected;
  await assert.rejects(peer.request("later"), /closed/);
});
