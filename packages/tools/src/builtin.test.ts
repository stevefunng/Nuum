import { testTempDir } from "../../../scripts/test-temp.mjs";
import assert from "node:assert/strict";
import { mkdir, readFile, stat, utimes, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { test, type TestContext } from "node:test";
import { createSandbox } from "@nuum/sandbox";
import {
  builtinTools,
  deleteTool,
  globTool,
  grepTool,
  lsTool,
  multiStrReplaceTool,
  readTool,
  shellTool,
  strReplaceTool,
  writeTool
} from "./builtin.js";
import type { Tool } from "./types.js";

async function fixture(t: TestContext) {
  const home = await testTempDir(path.join(tmpdir(), "nuum-tools-"));
  const project = path.join(home, "project");
  const scratch = path.join(home, "data", "agents", "a1", "scratch");
  await Promise.all([mkdir(project, { recursive: true }), mkdir(scratch, { recursive: true })]);
  const controller = new AbortController();
  const context = {
    runId: "run-1",
    abortSignal: controller.signal,
    sandbox: createSandbox({
      roots: { home, project, scratch, denied: [] },
      permission: "never" as const
    })
  };
  t.after(async () => {
    controller.abort();
    await context.sandbox.disposeShell();
  });
  return {
    home,
    project,
    scratch,
    context,
    async run(tool: Tool, input: Record<string, unknown>): Promise<string> {
      const output = await tool.execute(input, context);
      if (typeof output !== "string") throw new Error("expected a text-only tool result");
      return output;
    }
  };
}

test("the rebuilt local tool surface ends with the persistent shell", () => {
  assert.deepEqual(
    builtinTools.map((tool) => tool.definition.name),
    ["read", "write", "str_replace", "multi_str_replace", "delete", "ls", "glob", "grep", "shell", "request_network", "external_operation"]
  );
  assert.equal(shellTool.definition.action, "run-command");
});

test("read supports one-based ranges, optional line numbers, and empty files", async (t) => {
  const item = await fixture(t);
  const file = path.join(item.project, "lines.txt");
  await writeFile(file, "alpha\nbeta\ngamma\ndelta");
  assert.equal(
    await item.run(readTool, { path: file, offset: 2, limit: 2, include_line_numbers: true }),
    "2|beta\n3|gamma\n\n[Showing lines 2-3 of 4. 1 line remains.]"
  );
  assert.equal(await item.run(readTool, { path: file, offset: 2, limit: 1 }), "beta\n\n[Showing line 2 of 4. 2 lines remain.]");

  const empty = path.join(item.project, "empty.txt");
  await writeFile(empty, "");
  assert.equal(await item.run(readTool, { path: empty }), "File is empty.");
  await assert.rejects(() => item.run(readTool, { path: file, offset: 0 }), /offset must be an integer >= 1/i);
});

test("read truncates oversized output with a useful continuation range", async (t) => {
  const item = await fixture(t);
  const file = path.join(item.project, "large.txt");
  await writeFile(file, Array.from({ length: 5_000 }, (_, index) => `line-${index + 1}-${"x".repeat(20)}`).join("\n"));
  const output = await item.run(readTool, { path: file, include_line_numbers: true });
  assert.ok(output.length < 40_000);
  assert.match(output, /Output truncated at line \d+ of 5000/);
  assert.match(output, /Call read again with offset=/);
});

test("read returns supported images as multimodal model input", async (t) => {
  const item = await fixture(t);
  const file = path.join(item.project, "pixel.png");
  const bytes = Buffer.from("89504e470d0a1a0a", "hex");
  await writeFile(file, bytes);
  const output = await readTool.execute({ path: file }, item.context);
  assert.notEqual(typeof output, "string");
  if (typeof output === "string") return;
  assert.match(output.text, /Read image file: .*\/pixel\.png$/);
  assert.deepEqual(output.images, [{ mimeType: "image/png", data: bytes.toString("base64") }]);
});

test("write returns a compact diff and line counts for create and overwrite", async (t) => {
  const item = await fixture(t);
  const file = path.join(item.project, "write.txt");
  const created = await item.run(writeTool, { path: file, content: "one\ntwo" });
  assert.match(created, /Created .*write\.txt \(\+2\/-0\)/);
  assert.match(created, /\+one\n\+two/);

  const updated = await item.run(writeTool, { path: file, content: "one\nthree\nfour" });
  assert.match(updated, /Updated .*write\.txt \(\+2\/-1\)/);
  assert.match(updated, /-two/);
  assert.match(updated, /\+three/);
  assert.equal(await readFile(file, "utf8"), "one\nthree\nfour");
});

test("str_replace is unique by default and explains how to recover from ambiguous matches", async (t) => {
  const item = await fixture(t);
  const file = path.join(item.project, "replace.txt");
  await writeFile(file, "red blue red");
  await assert.rejects(
    () => item.run(strReplaceTool, { path: file, old_string: "red", new_string: "green" }),
    /matched 2 times.*more surrounding context.*replace_all/si
  );
  assert.equal(await readFile(file, "utf8"), "red blue red");
  const output = await item.run(strReplaceTool, {
    path: file,
    old_string: "red",
    new_string: "green",
    replace_all: true
  });
  assert.match(output, /Replaced 2 occurrences/);
  assert.match(output, /\+1\/-1/);
  assert.equal(await readFile(file, "utf8"), "green blue green");

  await assert.rejects(
    () => item.run(strReplaceTool, { path: file, old_string: "purple", new_string: "" }),
    /matched 0 times.*read the file/si
  );
});

test("multi_str_replace applies all edits in one atomic write", async (t) => {
  const item = await fixture(t);
  const file = path.join(item.project, "multi.txt");
  await writeFile(file, "alpha beta gamma");
  const output = await item.run(multiStrReplaceTool, {
    path: file,
    edits: [
      { old_string: "alpha", new_string: "A" },
      { old_string: "gamma", new_string: "G" }
    ]
  });
  assert.match(output, /Applied 2 edits/);
  assert.equal(await readFile(file, "utf8"), "A beta G");

  await assert.rejects(
    () => item.run(multiStrReplaceTool, {
      path: file,
      edits: [
        { old_string: "A", new_string: "changed" },
        { old_string: "missing", new_string: "nope" }
      ]
    }),
    /edit 2.*matched 0 times/si
  );
  assert.equal(await readFile(file, "utf8"), "A beta G");
});

test("delete removes files and directory trees", async (t) => {
  const item = await fixture(t);
  const directory = path.join(item.project, "obsolete");
  await mkdir(directory);
  await writeFile(path.join(directory, "old.txt"), "old");
  assert.match(await item.run(deleteTool, { path: directory }), /Deleted directory/);
  await assert.rejects(() => stat(directory), /ENOENT/);
});

test("ls renders a deterministic directory tree", async (t) => {
  const item = await fixture(t);
  await mkdir(path.join(item.project, "src", "nested"), { recursive: true });
  await writeFile(path.join(item.project, "README.md"), "readme");
  await writeFile(path.join(item.project, "src", "index.ts"), "code");
  const output = await item.run(lsTool, { path: item.project });
  assert.match(output, /project\//);
  assert.match(output, /├── src\//);
  assert.match(output, /│   ├── nested\//);
  assert.match(output, /└── README\.md/);
});

test("glob prepends a recursive prefix and sorts newest matches first", async (t) => {
  const item = await fixture(t);
  const nested = path.join(item.project, "src");
  await mkdir(nested);
  const oldFile = path.join(item.project, "old.ts");
  const newFile = path.join(nested, "new.ts");
  await writeFile(oldFile, "old");
  await writeFile(newFile, "new");
  await utimes(oldFile, new Date(1_000), new Date(1_000));
  await utimes(newFile, new Date(2_000), new Date(2_000));
  const output = await item.run(globTool, { glob_pattern: "*.ts", target_directory: item.project });
  assert.ok(output.indexOf(newFile) < output.indexOf(oldFile));
  assert.doesNotMatch(output, /README/);
});

test("grep maps the supported rg options and output modes", async (t) => {
  const item = await fixture(t);
  await mkdir(path.join(item.project, "src"));
  await writeFile(path.join(item.project, "src", "one.ts"), "Alpha\nsecond\nalpha");
  await writeFile(path.join(item.project, "src", "two.txt"), "alpha");

  const content = await item.run(grepTool, {
    pattern: "alpha",
    path: item.project,
    glob: "*.ts",
    "-i": true,
    output_mode: "content",
    head_limit: 2,
    offset: 1
  });
  assert.match(content, /one\.ts/);
  assert.match(content, /alpha/i);
  assert.equal(content.split("\n").length, 1);

  const files = await item.run(grepTool, {
    pattern: "alpha",
    path: item.project,
    output_mode: "files_with_matches"
  });
  assert.match(files, /one\.ts/);
  assert.match(files, /two\.txt/);

  const noMatches = await item.run(grepTool, { pattern: "does-not-exist", path: item.project });
  assert.equal(noMatches, "No matches found.");
  await assert.rejects(
    () => item.run(grepTool, { pattern: "x", output_mode: "everything" }),
    /output_mode must be one of/iu
  );
});

test("shell starts and re-inspects a persistent job with validated arguments", async (t) => {
  const item = await fixture(t);
  item.context.sandbox.setPermission("always");
  const started = await item.run(shellTool, { command: "printf hello", block_until_ms: 2_000 });
  assert.match(started, /completed with exit code 0/);
  assert.match(started, /output tail:\nhello/);
  assert.match(started, /full output: .*\/terminals\/.*\.txt/);
  const shellId = started.match(/Shell job ([0-9a-f-]{36})/)?.[1];
  assert.ok(shellId);
  const inspected = await item.run(shellTool, { shell_id: shellId });
  assert.match(inspected, /completed with exit code 0/);
  await assert.rejects(
    () => item.run(shellTool, { command: "pwd", shell_id: shellId }),
    /exactly one of command or shell_id/i
  );
});
