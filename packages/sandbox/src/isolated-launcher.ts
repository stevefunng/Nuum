/** Runs outside the sandbox; stdin is a private daemon pipe, never a tool-controlled config file. */
import { spawn } from "node:child_process";
import { createInterface } from "node:readline";
import { SandboxManager, type SandboxRuntimeConfig } from "@anthropic-ai/sandbox-runtime";

const lines = createInterface({ input: process.stdin });
const iterator = lines[Symbol.asyncIterator]();
const first = await iterator.next();
if (first.done) throw new Error("Missing isolation configuration");
const config = JSON.parse(first.value) as { policy: SandboxRuntimeConfig; command: string; cwd: string; env: Record<string, string>; payload: string };
if (!SandboxManager.isSupportedPlatform()) throw new Error("OS sandbox is unavailable on this platform");
const dependencies = await SandboxManager.checkDependenciesAsync();
if (dependencies.errors.length) throw new Error(dependencies.errors.join("; "));
await SandboxManager.initialize(config.policy, undefined, false);
const wrapped = await SandboxManager.wrapWithSandboxArgv(config.command, "/bin/bash", undefined, undefined, config.cwd);
const [executable, ...args] = wrapped.argv;
if (!executable) throw new Error("Sandbox returned no executable");
const child = spawn(executable, args, { cwd: config.cwd, env: { ...wrapped.env, ...config.env }, stdio: ["pipe", "inherit", "inherit"] });
child.stdin.write(config.payload + "\n");
void (async () => { for await (const line of { [Symbol.asyncIterator]: () => iterator }) child.stdin.write(line + "\n"); stop(); })();
let stopping = false;
function stop() {
  if (stopping) return;
  stopping = true;
  try { process.kill(-process.pid, "SIGTERM"); } catch { child.kill("SIGTERM"); }
  setTimeout(() => { try { process.kill(-process.pid, "SIGKILL"); } catch { child.kill("SIGKILL"); } }, 1500).unref();
}
process.on("SIGTERM", stop);
process.on("SIGINT", stop);
child.on("error", error => { process.stderr.write(String(error)); stop(); });
child.on("close", code => { void SandboxManager.reset().finally(() => { try { process.kill(-process.pid, "SIGKILL"); } catch { process.exit(code ?? 1); } }); });
