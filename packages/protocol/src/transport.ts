import { RpcError } from "./errors.js";
import {
  isJsonRpcEvent,
  isJsonRpcRequest,
  isJsonRpcResponse,
  type JsonRpcEvent,
  type JsonRpcId,
  type JsonRpcRequest,
  type JsonRpcResponse
} from "./rpc-frame.js";

export type RpcHandler = (method: string, params: unknown) => Promise<unknown> | unknown;
export type RpcEventHandler = (method: string, params: unknown) => void;

export interface ByteDuplex {
  write(line: string): void;
  onLine(listener: (line: string) => void): () => void;
}

export class JsonRpcPeer {
  private readonly pending = new Map<
    string,
    { resolve: (value: unknown) => void; reject: (error: unknown) => void }
  >();
  private seq = 0;
  private closed: Error | undefined;
  private handler: RpcHandler | undefined;
  private eventHandler: RpcEventHandler | undefined;

  constructor(private readonly duplex: ByteDuplex) {
    duplex.onLine((line) => this.receive(line));
  }

  close(error = new Error("RPC connection closed")): void {
    if (this.closed) return;
    this.closed = error;
    for (const waiter of this.pending.values()) waiter.reject(error);
    this.pending.clear();
  }

  setHandler(handler: RpcHandler): void {
    this.handler = handler;
  }

  onEvent(handler: RpcEventHandler): void {
    this.eventHandler = handler;
  }

  async request(method: string, params?: unknown): Promise<unknown> {
    if (this.closed) throw this.closed;
    const id = String(++this.seq);
    const frame: JsonRpcRequest = { jsonrpc: "2.0", id, method, params };
    const result = new Promise<unknown>((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
    });
    try { this.duplex.write(JSON.stringify(frame)); }
    catch (error) { this.close(error instanceof Error ? error : new Error(String(error))); }
    return result;
  }

  notify(method: string, params?: unknown): void {
    if (this.closed) return;
    const frame: JsonRpcEvent = { jsonrpc: "2.0", method, params };
    this.duplex.write(JSON.stringify(frame));
  }

  private receive(line: string): void {
    let parsed: unknown;
    try {
      parsed = JSON.parse(line);
    } catch {
      return;
    }
    if (isJsonRpcResponse(parsed)) {
      this.settle(parsed);
      return;
    }
    if (isJsonRpcRequest(parsed)) {
      void this.dispatch(parsed);
      return;
    }
    if (isJsonRpcEvent(parsed)) {
      this.eventHandler?.(parsed.method, parsed.params);
    }
  }

  private settle(response: JsonRpcResponse): void {
    const key = String(response.id);
    const waiter = this.pending.get(key);
    if (!waiter) return;
    this.pending.delete(key);
    if (response.error) {
      waiter.reject(new RpcError(response.error.code, response.error.message, response.error.data));
      return;
    }
    waiter.resolve(response.result);
  }

  private async dispatch(request: JsonRpcRequest): Promise<void> {
    const reply = (body: Omit<JsonRpcResponse, "jsonrpc" | "id">): void => {
      if (this.closed) return;
      const frame: JsonRpcResponse = { jsonrpc: "2.0", id: request.id as JsonRpcId, ...body };
      this.duplex.write(JSON.stringify(frame));
    };
    if (!this.handler) {
      reply({ error: { code: -32601, message: `No handler for ${request.method}` } });
      return;
    }
    try {
      const result = await this.handler(request.method, request.params);
      reply({ result });
    } catch (error) {
      if (error instanceof RpcError) {
        reply({ error: { code: error.code, message: error.message, data: error.data } });
        return;
      }
      const message = error instanceof Error ? error.message : String(error);
      reply({ error: { code: -32000, message } });
    }
  }
}

export function createStdioDuplex(
  stdin: NodeJS.ReadableStream,
  stdout: NodeJS.WritableStream
): ByteDuplex {
  const listeners = new Set<(line: string) => void>();
  let buffer = "";
  stdin.setEncoding?.("utf8");
  stdin.on("data", (chunk: string | Buffer) => {
    buffer += typeof chunk === "string" ? chunk : chunk.toString("utf8");
    let index = buffer.indexOf("\n");
    while (index >= 0) {
      const line = buffer.slice(0, index).trim();
      buffer = buffer.slice(index + 1);
      if (line.length > 0) {
        for (const listener of listeners) listener(line);
      }
      index = buffer.indexOf("\n");
    }
  });
  return {
    write(line) {
      stdout.write(`${line}\n`);
    },
    onLine(listener) {
      listeners.add(listener);
      return () => {
        listeners.delete(listener);
      };
    }
  };
}

export { executionRpc } from "./execution-client.js";
