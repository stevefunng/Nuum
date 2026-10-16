import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import {
  HostErrorCode,
  KernelMethods,
  RpcError,
  type KernelHello,
  type SummarizeRunParams,
  type SummarizeRunResult,
  type TurnStartParams,
  type TurnToolDecision,
  type TurnContextResult,
  type TurnToolResult
} from "@nuum/protocol";
import { JsonRpcPeer, createStdioDuplex } from "@nuum/protocol/node";

export interface KernelClient {
  hello(): Promise<KernelHello>;
  start(params: TurnStartParams): Promise<unknown>;
  cancel(runId: string): Promise<unknown>;
  decide(params: TurnToolDecision, deny?: boolean): Promise<unknown>;
  provideContext?(params: TurnContextResult): Promise<unknown>;
  provideToolResult(params: TurnToolResult): Promise<unknown>;
  disposeShell(terminals: string): Promise<unknown>;
  cancelSummary?(runId: string): Promise<unknown>;
  summarize(params: SummarizeRunParams): Promise<SummarizeRunResult>;
  tools(): Promise<unknown>;
  onEvent(handler: (method: string, params: unknown) => void): void;
  onExit?(handler: () => void): void;
  dispose(): void;
}

export function spawnKernelClient(command: string, args: string[]): KernelClient {
  const child: ChildProcessWithoutNullStreams = spawn(command, args, {
    stdio: ["pipe", "pipe", "pipe"]
  });
  const peer = new JsonRpcPeer(createStdioDuplex(child.stdout, child.stdin));
  child.stdin.on("error", error => peer.close(error));
  child.stdout.on("error", error => peer.close(error));
  child.on("error", error => peer.close(error));
  child.once("exit", () => peer.close(new Error("Kernel connection closed")));
  child.stderr.on("data", (chunk) => {
    process.stderr.write(chunk);
  });
  return {
    hello: () => peer.request(KernelMethods.sysHello) as Promise<KernelHello>,
    start: (params) => peer.request(KernelMethods.turnStart, params),
    cancel: (runId) => peer.request(KernelMethods.turnCancel, { runId }),
    decide: (params, deny) =>
      peer.request(deny ? KernelMethods.turnDenyTool : KernelMethods.turnApproveTool, params),
    provideContext: params => peer.request(KernelMethods.turnProvideContext, params),
    provideToolResult: (params) => peer.request(KernelMethods.turnProvideToolResult, params),
    disposeShell: (terminals) => {
      if (child.exitCode !== null || child.signalCode !== null || child.stdin.destroyed) {
        return Promise.resolve({ ok: true });
      }
      return peer.request(KernelMethods.shellDispose, { terminals });
    },
    cancelSummary: runId => peer.request(KernelMethods.summarizeCancel, { runId }),
    summarize: (params) => peer.request(KernelMethods.summarizeRun, params) as Promise<SummarizeRunResult>,
    tools: () => peer.request(KernelMethods.toolsList),
    onEvent: (handler) => peer.onEvent(handler),
    onExit: (handler) => { child.once("exit", handler); },
    dispose() {
      peer.close();
      child.kill("SIGTERM");
    }
  };
}

export async function requireKernel(client: KernelClient | null): Promise<KernelClient> {
  if (!client) throw new RpcError(HostErrorCode.KERNEL_DOWN, "Kernel is not available");
  return client;
}
