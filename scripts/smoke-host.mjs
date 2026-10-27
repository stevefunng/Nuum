import { spawn } from "node:child_process";
import path from "node:path";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { cleanupTestExecutor } from "./test-executor.mjs";

const root = path.resolve(import.meta.dirname, "..");
const hostEntry = path.join(root, "packages/host/dist/main.js");
const kernelEntry = path.join(root, "packages/kernel/dist/main.js");

function alive(pid) {
  if (!Number.isInteger(pid) || pid <= 0) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    return error.code === "EPERM";
  }
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function waitGone(pid) {
  const deadline = Date.now() + 5000;
  while (alive(pid)) {
    if (Date.now() >= deadline) throw new Error(`Process ${pid} did not exit; preserving smoke data`);
    await sleep(50);
  }
}

async function kernelPidFor(hostPid) {
  if (!alive(hostPid)) return null;
  return new Promise((resolve, reject) => {
    const ps = spawn("pgrep", ["-P", String(hostPid), "-f", kernelEntry]);
    ps.once("error", reject);
    let out = "";
    ps.stdout.on("data", (chunk) => (out += chunk));
    ps.on("close", (code) => {
      if (code !== 0 && code !== 1) reject(new Error(`pgrep failed: ${code}`));
      else resolve(Number(out.trim().split("\n")[0]) || null);
    });
  });
}

function spawnTracked(...args) {
  const child = spawn(...args);
  const closed = new Promise((resolve) => child.once("close", resolve));
  child.on("error", (error) => console.error("smoke child failed", error));
  return {
    child,
    async stop() {
      if (child.exitCode === null && child.signalCode === null) child.kill("SIGTERM");
      const timer = setTimeout(() => child.kill("SIGKILL"), 2000);
      try { await closed; } finally { clearTimeout(timer); }
    }
  };
}

async function rpcSmoke() {
  const dataDir = await mkdtemp(path.join(tmpdir(), "nuum-smoke-"));
  let tracked;
  let kernelPid;
  try {
    tracked = spawnTracked("node", [hostEntry, "--data-dir", dataDir, "--kernel-entry", kernelEntry, "--documents-dir", path.join(dataDir, "Documents")], {
      stdio: ["pipe", "pipe", "inherit"]
    });
    const host = tracked.child;
    const lines = [];
    host.stdout.setEncoding("utf8");
    host.stdout.on("data", (chunk) => {
      for (const line of chunk.split("\n").filter(Boolean)) lines.push(line);
    });
    const send = (obj) => host.stdin.write(`${JSON.stringify(obj)}\n`);

    send({ jsonrpc: "2.0", id: "1", method: "sys.hello" });
    await sleep(400);
    send({ jsonrpc: "2.0", id: "2", method: "agent.send", params: { id: "missing", content: "hi" } });
    await sleep(400);
    kernelPid = await kernelPidFor(host.pid);
    await tracked.stop();

    const hello = lines.find((line) => line.includes("nuum-host"));
    const missing = lines.find((line) => line.includes("2001"));
    if (!hello || !missing) {
      console.error(lines);
      throw new Error("host rpc smoke failed");
    }
    console.log("smoke ok", hello, missing);
  } finally {
    await tracked?.stop();
    await waitGone(kernelPid);
    await cleanupTestExecutor(dataDir);
    await rm(dataDir, { recursive: true, force: true });
  }
}

/**
 * 父进程被强杀时 Host 与 Kernel 必须自行退出。漏掉的话孤儿会一直持着 dataDir 锁，
 * 把下一次启动挡在门外 —— 这个回归在进程层，单元测试看不见。
 */
async function orphanSmoke() {
  const dataDir = await mkdtemp(path.join(tmpdir(), "nuum-orphan-"));
  let tracked;
  let hostPid;
  let kernelPid;
  try {
    tracked = spawnTracked(
      process.execPath,
      [
        "-e",
        `const { spawn } = require("node:child_process");
         const child = spawn("node", [${JSON.stringify(hostEntry)},
           "--data-dir", ${JSON.stringify(dataDir)},
           "--kernel-entry", ${JSON.stringify(kernelEntry)}, "--documents-dir", ${JSON.stringify(path.join(dataDir, "Documents"))}], { stdio: ["pipe", "pipe", "inherit"] });
         console.log(String(child.pid));
         setInterval(() => {}, 1000);`
      ],
      { stdio: ["pipe", "pipe", "inherit"] }
    );
    const shim = tracked.child;
    hostPid = await new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error("orphan smoke did not receive host PID")), 5000);
      const finish = (pid) => { clearTimeout(timer); resolve(pid); };
      shim.stdout.setEncoding("utf8");
      shim.stdout.once("data", (chunk) => finish(Number(chunk.trim())));
      shim.once("close", () => finish(null));
    });
    if (!alive(hostPid)) throw new Error("orphan smoke could not start host");
    await sleep(800);
    kernelPid = await kernelPidFor(hostPid);
    if (!alive(hostPid) || !kernelPid) throw new Error("orphan smoke could not start host and kernel");

    shim.kill("SIGKILL");
    await sleep(2000);

    const leaked = [alive(hostPid) && `host ${hostPid}`, alive(kernelPid) && `kernel ${kernelPid}`].filter(Boolean);
    if (leaked.length > 0) {
      throw new Error(`orphaned after parent SIGKILL: ${leaked.join(", ")}`);
    }
    console.log("orphan smoke ok", `host ${hostPid} and kernel ${kernelPid} exited with their parent`);
  } finally {
    await tracked?.stop();
    for (const pid of [hostPid, kernelPid]) {
      if (!alive(pid)) continue;
      try { process.kill(pid, "SIGKILL"); } catch (error) { if (error.code !== "ESRCH") throw error; }
      await waitGone(pid);
    }
    await cleanupTestExecutor(dataDir);
    await rm(dataDir, { recursive: true, force: true });
  }
}

await rpcSmoke();
await orphanSmoke();
