import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdtemp, mkdir, readdir, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";

for (const fail of [false, true]) {
  test(`temporary directories are cleaned after ${fail ? "failed" : "passed"} tests and resource teardown`, async () => {
    const root = await mkdtemp(path.join(tmpdir(), "nuum-cleanup-check-"));
    try {
      const owned = path.join(root, "owned");
      await mkdir(owned);
      const sentinel = path.join(root, "keep.txt");
      await writeFile(sentinel, "keep");
      const fixture = path.join(root, "fixture.test.mjs");
      await writeFile(fixture, `
        import assert from "node:assert/strict";
        import { writeFile, readFile, symlink } from "node:fs/promises";
        import { test } from "node:test";
        import { testTempDir } from ${JSON.stringify(new URL("./test-temp.mjs", import.meta.url).href)};
        test("fixture", async (t) => {
          const dir = await testTempDir(${JSON.stringify(path.join(owned, "nuum-agents-"))});
          await writeFile(dir + "/data", "open");
          await symlink(${JSON.stringify(sentinel)}, dir + "/external");
          t.after(async () => {
            assert.equal(await readFile(dir + "/data", "utf8"), "open");
            await writeFile(${JSON.stringify(path.join(root, "released"))}, "released");
          });
          if (${fail}) throw new Error("intentional fixture failure");
        });
      `);
      const env = { ...process.env };
      delete env.NODE_TEST_CONTEXT;
      const child = spawn(process.execPath, ["--test", fixture], { env, stdio: ["ignore", "pipe", "pipe"] });
      let output = "";
      child.stdout.on("data", (chunk) => { output += chunk; });
      child.stderr.on("data", (chunk) => { output += chunk; });
      const code = await new Promise((resolve, reject) => {
        child.on("error", reject);
        child.on("close", resolve);
      });
      assert.equal(code, fail ? 1 : 0, output);
      if (fail) assert.match(output, /intentional fixture failure/);
      assert.equal(await readFile(path.join(root, "released"), "utf8"), "released");
      assert.deepEqual(await readdir(owned), []);
      assert.equal(await readFile(sentinel, "utf8"), "keep");
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });
}
