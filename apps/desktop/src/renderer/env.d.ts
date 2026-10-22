import type { AgentSnapshot, AgentView, PublicSettings, ChatMessage, SecretsState } from "@nuum/protocol";

export interface NuumBridge {
  host: {
    request(method: string, params?: unknown): Promise<unknown>;
    onEvent(listener: (method: string, params: unknown) => void): () => void;
  };
  desktop: {
    showProactive(): Promise<void>;
    openProactiveAgent(agentId: string): Promise<void>;
    showMain(): Promise<void>;
    quit(): Promise<void>;
    openPath(file: string): Promise<string>;
    pickWorkspace(): Promise<string | null>;
    getSecrets(): Promise<SecretsState>;
    setSecrets(secrets: SecretsState): Promise<unknown>;
  };
}

declare global {
  interface Window {
    nuum: NuumBridge;
  }
}

export type { AgentSnapshot, AgentView, ChatMessage, PublicSettings, SecretsState };
