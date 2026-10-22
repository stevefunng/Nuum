#!/usr/bin/env node
import { readFile } from "node:fs/promises";
import path from "node:path";
import { startExecutor } from "./server.js";
const dataDir = process.argv[2];
if (!dataDir) throw new Error("Executor private data directory is required");
const { socket, token } = JSON.parse(await readFile(path.join(dataDir, "owner.json"), "utf8"));
const executor = await startExecutor(dataDir, socket, token);
let closing = false;
const close = () => {
  if (closing) return;
  closing = true;
  void executor.close().then(() => process.exit(0), error => { console.error(error); process.exit(1); });
};
process.on("SIGTERM", close);
process.on("SIGINT", close);
