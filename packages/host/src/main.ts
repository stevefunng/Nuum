#!/usr/bin/env node
import { homedir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { createHostServer } from "./server.js";

const here = path.dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const dataDir = readFlag("--data-dir") ?? path.join(homedir(), ".nuum");
const kernelCommand = readFlag("--kernel-command") ?? process.execPath;
const defaultKernel = path.resolve(here, "..", "..", "kernel", "dist", "main.js");
const kernelEntry = readFlag("--kernel-entry") ?? defaultKernel;

const runtime = await createHostServer({
  dataDir,
  privateDir: readFlag("--private-dir"),
  documentsDir: readFlag("--documents-dir") ?? path.join(homedir(), "Documents"),
  executorEntry: readFlag("--executor-entry") ?? path.resolve(here, "../../executor/dist/main.js"),
  kernelCommand,
  kernelArgs: kernelCommand === process.execPath ? [kernelEntry] : []
});
process.stdin.resume();

let shuttingDown = false;
function shutdown(): void {
  if (shuttingDown) return;
  shuttingDown = true;
  void runtime.dispose().finally(() => process.exit(0));
}

for (const signal of ["SIGTERM", "SIGINT", "SIGHUP"] as const) {
  process.once(signal, shutdown);
}

// Unexpected Desktop disconnect stops the harness, while accepted executor work can be adopted.
function detach(): void {
  if (shuttingDown) return;
  shuttingDown = true;
  void runtime.detach().finally(() => process.exit(0));
}
process.stdin.on("end", detach);
process.stdin.on("close", detach);

function readFlag(name: string): string | undefined {
  const index = args.indexOf(name);
  if (index < 0) return undefined;
  return args[index + 1];
}
