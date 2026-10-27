import { mkdtemp, rm } from "node:fs/promises";
import { after } from "node:test";

const directories = new Set();

// 文件级收尾晚于各用例的 t.after：重开 Store / Host 的用例也先释放全部资源。
after(async () => {
  const results = await Promise.allSettled(
    [...directories].map((directory) => rm(directory, { recursive: true, force: true }))
  );
  const errors = results.filter((result) => result.status === "rejected").map((result) => result.reason);
  if (errors.length) throw new AggregateError(errors, "Failed to clean test temporary directories");
  directories.clear();
});

/** 只记录本测试进程创建的目录，不扫描或清理其他运行留下的目录。 */
export async function testTempDir(prefix) {
  const directory = await mkdtemp(prefix);
  directories.add(directory);
  return directory;
}
