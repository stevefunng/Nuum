import { spawn } from "node:child_process";
import path from "node:path";
import { mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";

const root = path.resolve(import.meta.dirname, "..");
const hostEntry = path.join(root, "packages/host/dist/main.js");
const kernelEntry = path.join(root, "packages/kernel/dist/main.js");

function alive(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    return error.code === "EPERM";
  }
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function rpcSmoke() {
  const dataDir = await mkdtemp(path.join(tmpdir(), "nuum-smoke-"));
  const host = spawn("node", [hostEntry, "--data-dir", dataDir, "--kernel-entry", kernelEntry, "--documents-dir", path.join(dataDir, "Documents")], {
    stdio: ["pipe", "pipe", "inherit"]
  });
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
  host.kill("SIGTERM");

  const hello = lines.find((line) => line.includes("nuum-host"));
  const missing = lines.find((line) => line.includes("2001"));
  if (!hello || !missing) {
    console.error(lines);
    throw new Error("host rpc smoke failed");
  }
  console.log("smoke ok", hello, missing);
}

/**
 * 父进程被强杀时 Host 与 Kernel 必须自行退出。漏掉的话孤儿会一直持着 dataDir 锁，
 * 把下一次启动挡在门外 —— 这个回归在进程层，单元测试看不见。
 */
async function orphanSmoke() {
  const dataDir = await mkdtemp(path.join(tmpdir(), "nuum-orphan-"));
  const shim = spawn(
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
  const hostPid = await new Promise((resolve) => {
    shim.stdout.setEncoding("utf8");
    shim.stdout.once("data", (chunk) => resolve(Number(chunk.trim())));
  });
  await sleep(800);
  const kernelPid = await new Promise((resolve) => {
    const ps = spawn("pgrep", ["-P", String(hostPid), "-f", kernelEntry]);
    let out = "";
    ps.stdout.on("data", (chunk) => (out += chunk));
    ps.on("close", () => resolve(Number(out.trim().split("\n")[0]) || null));
  });
  if (!alive(hostPid) || !kernelPid) throw new Error("orphan smoke could not start host and kernel");

  shim.kill("SIGKILL");
  await sleep(2000);

  const leaked = [alive(hostPid) && `host ${hostPid}`, alive(kernelPid) && `kernel ${kernelPid}`].filter(Boolean);
  if (leaked.length > 0) {
    for (const pid of [hostPid, kernelPid]) {
      try {
        process.kill(pid, "SIGKILL");
      } catch {
        // 已经退出了
      }
    }
    throw new Error(`orphaned after parent SIGKILL: ${leaked.join(", ")}`);
  }
  console.log("orphan smoke ok", `host ${hostPid} and kernel ${kernelPid} exited with their parent`);
}

await rpcSmoke();
await orphanSmoke();
