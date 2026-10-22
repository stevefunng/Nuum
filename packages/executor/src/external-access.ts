import { lstat, realpath, readFile } from "node:fs/promises";
import { homedir } from "node:os";
import path from "node:path";
import { createHash } from "node:crypto";
import { ExternalOperation, commandRule, staticShellWords, splitShellCommands, type ExternalGrant, type ExecutionContext } from "@nuum/protocol";

const inside = (root: string, target: string) => target === root || target.startsWith(root + path.sep);
export async function canonicalTarget(value: string): Promise<string> {
  if (!path.isAbsolute(value)) throw new Error("External paths must be absolute");
  const resolved = path.resolve(value);
  try { return await realpath(resolved); }
  catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
    // Only an absent final file is permitted; its parent must already exist.
    await lstat(resolved).then(() => { throw new Error("Dangling symlink is not an authorized target"); }, e => { if (e.code !== "ENOENT") throw e; });
    return path.join(await realpath(path.dirname(resolved)), path.basename(resolved));
  }
}
export async function prepareExternal(input: unknown, context: ExecutionContext, protectedRoot: string): Promise<{ operation: ExternalOperation; grant: ExternalGrant; target: string }> {
  const operation = ExternalOperation.parse(input);
  const home = await realpath(homedir());
  const protectedPaths = await Promise.all([protectedRoot, ...(context.protectedPaths ?? [])].map(p => realpath(p)));
  const validate = async (value: string) => {
    const target = await canonicalTarget(value);
    if (!inside(home, target) || target === home) throw new Error("Choose a specific path inside your home folder");
    if (protectedPaths.some(protectedPath => inside(protectedPath, target) || inside(target, protectedPath))) throw new Error("Nuum private configuration is not available to tools");
    return target;
  };
  const grant: ExternalGrant = { environment: "local", workspaceId: context.workspaceId, operation: operation.operation,
    readPaths: [], writePaths: [], networkTargets: [...new Set(operation.networkTargets.map(target => target.toLowerCase()))].sort(), overwrite: operation.overwrite, fingerprints: {} };
  if (operation.operation === "shell") {
    if (!operation.command) throw new Error("External shell requires command");
    grant.cwd = await validate(operation.cwd ?? context.root);
    grant.readPaths = [...new Set(await Promise.all(operation.readPaths.map(validate)))].sort();
    grant.writePaths = [...new Set(await Promise.all(operation.writePaths.map(validate)))].sort();
    if (!inside(context.root, grant.cwd) && ![...grant.readPaths, ...grant.writePaths].some(p => inside(p, grant.cwd!))) throw new Error("External cwd must be included in requested paths");
    grant.command = commandRule(operation.command);
    // Query grammars may generalize arguments, but executable and directly referenced
    // file fingerprints still apply; directory grants remain explicit resource permissions.
    for (const p of [...grant.readPaths, ...grant.writePaths]) {
      const stat = await lstat(p).catch(() => null);
      if (stat?.isFile()) {
        if (stat.size > 16 * 1024 * 1024) throw new Error("Use a directory resource grant for files larger than 16 MiB");
        grant.fingerprints[p] = createHash("sha256").update(await readFile(p)).digest("hex");
      }
    }
    const chain = splitShellCommands(operation.command);
    grant.rememberable = chain !== undefined;
    for (const segment of chain?.commands ?? []) {
      const words = staticShellWords(segment)!;
      const executable = words[0]!;
      let executablePath: string | undefined;
      for (const candidate of executable.includes("/") ? [path.resolve(grant.cwd, executable)] : ["/usr/bin", "/bin", "/usr/sbin", "/sbin"].map(dir => path.join(dir, executable))) {
        if ((await lstat(candidate).catch(() => null))?.isFile() || (await lstat(candidate).catch(() => null))?.isSymbolicLink()) { executablePath = await realpath(candidate); break; }
      }
      if (!executablePath) { grant.rememberable = false; continue; }
      for (const candidate of [executablePath, ...words.slice(1).filter(word => !word.startsWith("-")).map(word => path.resolve(grant.cwd!, word))]) {
        const info = await lstat(candidate).catch(() => null);
        if (!info?.isFile()) continue;
        if (info.size > 16 * 1024 * 1024) { grant.rememberable = false; continue; }
        const canonical = await realpath(candidate);
        if (protectedPaths.some(protectedPath => inside(protectedPath, canonical))) throw new Error("Nuum private configuration is not available to tools");
        grant.fingerprints[canonical] = createHash("sha256").update(await readFile(canonical)).digest("hex");
      }
    }
    return { operation, grant, target: operation.command };
  }
  if (!operation.source) throw new Error("File operation requires source");
  grant.source = await validate(operation.source);
  if (operation.operation !== "read") {
    if (!operation.destination) throw new Error("Copy requires destination");
    grant.destination = await validate(operation.destination);
    if (operation.operation === "export" && !inside(context.root, grant.source)) throw new Error("Export source must be inside the workspace");
    if (operation.operation === "import" && !inside(context.root, grant.destination)) throw new Error("Import destination must be inside the workspace");
  }
  const actual = { ...operation, source: grant.source, destination: grant.destination };
  if (operation.resourceRoot) {
    grant.scope = "directory";
    const scope = await validate(operation.resourceRoot);
    if (!(await lstat(scope)).isDirectory()) throw new Error("Resource root must be an existing directory");
    if (operation.operation === "export") {
      if (!inside(scope, grant.destination!)) throw new Error("Export target is outside requested directory");
      if (operation.overwrite) throw new Error("Directory export permission only creates new files; request a specific file to overwrite");
      grant.destination = scope; grant.source = context.root;
    } else {
      if (!inside(scope, grant.source)) throw new Error("Source is outside requested directory");
      grant.source = scope;
      if (operation.operation === "import") grant.destination = context.root;
    }
  }
  return { operation: actual, grant, target: operation.resourceRoot ? (operation.operation === "export" ? grant.destination! : grant.source!) : actual.destination ?? actual.source! };
}
