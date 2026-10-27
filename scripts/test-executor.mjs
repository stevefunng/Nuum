import { readFile, rmdir } from "node:fs/promises";
import path from "node:path";
import { executionRpc } from "../packages/protocol/dist/transport.js";

async function readJson(file) {
  try { return JSON.parse(await readFile(file, "utf8")); }
  catch (error) { if (error.code === "ENOENT") return null; throw error; }
}

function alive(pid) {
  try { process.kill(pid, 0); return true; }
  catch (error) { if (error.code === "ESRCH") return false; throw error; }
}

// 调用前先关闭 Host / client，避免监督器再次拉起 daemon。
export async function cleanupTestExecutor(dataDir) {
  const directory = path.join(dataDir, "executor");
  const owner = await readJson(path.join(directory, "owner.json"));
  if (!owner) return;
  const discovery = await readJson(path.join(directory, "discovery.json"));
  if (discovery) {
    if (owner.socket !== discovery.socket || !Number.isInteger(discovery.pid) || discovery.pid <= 0) {
      throw new Error("Invalid test executor identity; preserving temporary data");
    }
    try { await executionRpc({ ...owner, instance: discovery.instance }, "shutdown"); }
    catch (error) {
      // stop() 可能已关闭 socket，daemon 正在完成退出；仍须等待 PID 消失。
      if (alive(discovery.pid) && error.code !== "ENOENT" && error.code !== "ECONNREFUSED") throw error;
    }
  }
  const deadline = Date.now() + 5000;
  while (true) {
    // 不递归删除 socket 目录：还有服务或文件时保留数据并报错。
    if (!discovery || !alive(discovery.pid)) {
      try { await rmdir(path.dirname(owner.socket)); return; }
      catch (error) {
        if (error.code === "ENOENT") return;
        if (error.code !== "ENOTEMPTY") throw error;
      }
    }
    if (Date.now() >= deadline) throw new Error("Test executor did not stop; preserving temporary data");
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
}
