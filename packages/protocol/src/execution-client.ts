import { request } from "node:http";
import type { ExecutionEndpoint } from "./execution.js";

/** Transport only: permissions are never inferred by clients. No automatic mutation retries. */
export async function executionRpc<T = unknown>(endpoint: ExecutionEndpoint, method: string, params: unknown = {}): Promise<T> {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify({ instance: endpoint.instance, method, params });
    const req = request({ socketPath: endpoint.socket, path: "/rpc", method: "POST", headers: {
      authorization: `Bearer ${endpoint.token}`, "content-type": "application/json", "content-length": Buffer.byteLength(body)
    } }, response => {
      const chunks: Buffer[] = []; let size = 0;
      response.on("data", (chunk: Buffer) => {
        size += chunk.length;
        if (size > 16 * 1024 * 1024) { response.destroy(new Error("Execution response exceeds limit")); return; }
        chunks.push(chunk);
      });
      response.on("error", reject);
      response.on("end", () => {
        try {
          const value = JSON.parse(Buffer.concat(chunks).toString()) as { result: T; error?: string };
          if (response.statusCode !== 200 || value.error) reject(new Error(value.error ?? "Execution service refused request"));
          else resolve(value.result);
        } catch (error) { reject(error); }
      });
    });
    req.on("error", reject);
    req.setTimeout(10_000, () => req.destroy(new Error("Execution service connection timed out")));
    req.end(body);
  });
}
