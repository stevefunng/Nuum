import { readFile, copyFile, stat } from "node:fs/promises";
import { constants } from "node:fs";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
/** Every tool and child process inherits this worker's OS sandbox. No Host credentials enter here. */
import { createInterface } from "node:readline";
import { createSandbox, disposeAllShells, hasRunningShellJobs } from "@nuum/sandbox";
import { builtinTools } from "@nuum/tools";
import type { ExecutionContext, ExecutionRequest } from "@nuum/protocol";

const input = createInterface({ input: process.stdin });
const lines = input[Symbol.asyncIterator]();
const first = await lines.next();
if (first.done) throw new Error("Missing tool context");
const { context, scratch } = JSON.parse(first.value) as { context: ExecutionContext; scratch: string };
const abort = new AbortController();
const shutdown = () => { abort.abort(); void disposeAllShells().finally(() => process.exit(0)); };
process.on("SIGTERM", shutdown);
process.on("SIGINT", shutdown);
const sandbox = createSandbox({ roots: { home: context.root, project: context.root, scratch, terminals: `${scratch}/terminals`, denied: [], readOnly: context.readOnly }, permission: "always" });
process.stdout.write(JSON.stringify({ ready: true }) + "\n");
const heartbeat = setInterval(() => { void hasRunningShellJobs().then(busy => process.stdout.write(JSON.stringify({ busy }) + "\n")); }, 500);
for await (const line of { [Symbol.asyncIterator]: () => lines }) {
  const request = JSON.parse(line) as ExecutionRequest;
  try {
    if (request.name === "external_operation") {
      const operation = request.input;
      let output: string;
      if (operation.operation === "shell") {
        const command = String(operation.command);
        const result = await promisify(execFile)("/bin/bash", ["--noprofile", "--norc", "-c", command], {
          cwd: String(operation.cwd ?? context.root), signal: abort.signal, timeout: 120000, maxBuffer: 100000,
          env: { PATH: "/usr/bin:/bin:/usr/sbin:/sbin", HOME: context.root, TMPDIR: `${scratch}/tmp`, LANG: "en_US.UTF-8", ...Object.fromEntries(Object.entries(process.env).filter(([key]) => /^(HTTP_PROXY|HTTPS_PROXY|ALL_PROXY|NO_PROXY|http_proxy|https_proxy|all_proxy|no_proxy)$/.test(key))) }
        });
        output = result.stdout + result.stderr;
      } else {
        const source = String(operation.source);
        const info = await stat(source);
        if (!info.isFile()) throw new Error("Only regular files are supported");
        if (operation.operation === "read") {
          if (info.size > 100000) throw new Error("File exceeds 100 KB; import it into the workspace to process it");
          output = await readFile(source, "utf8");
        } else {
          await copyFile(source, String(operation.destination), operation.overwrite === true ? 0 : constants.COPYFILE_EXCL);
          output = `Copied file to ${operation.destination}`;
        }
      }
      process.stdout.write(JSON.stringify({ id: request.id, result: { state: "finished", ok: true, output } }) + "\n");
      continue;
    }
    const tool = builtinTools.find(candidate => candidate.definition.name === request.name);
    if (!tool) throw new Error(`Unknown execution tool: ${request.name}`);
    const value = await tool.execute(request.input, { runId: request.id, sandbox, abortSignal: abort.signal });
    process.stdout.write(JSON.stringify({ id: request.id, result: typeof value === "string" ? { state: "finished", ok: true, output: value } : { state: "finished", ok: true, output: value.text, images: value.images } }) + "\n");
  } catch (error) {
    process.stdout.write(JSON.stringify({ id: request.id, result: { state: "finished", ok: false, output: error instanceof Error ? error.message : String(error) } }) + "\n");
  }
}
clearInterval(heartbeat);
await disposeAllShells();
