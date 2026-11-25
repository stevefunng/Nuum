import NuumContracts

struct ShellTool: Tool {
    let definition = ToolDefinition(
        name: "shell",
        description: "Run a command in this agent's persistent bash, or inspect a background job by shell_id.",
        inputSchema: JSONSchema.object(
            [
                "command": JSONSchema.string(),
                "working_directory": JSONSchema.string(),
                "block_until_ms": JSONSchema.integer(minimum: 0, default: 30_000),
                "shell_id": JSONSchema.string(),
            ],
            oneOf: [
                JSONSchema.required(["command"]),
                JSONSchema.required(["shell_id"]),
            ]
        ),
        mutating: true,
        action: .runCommand
    )

    func execute(_ input: [String: JSONValue], sandbox: RunSandbox) throws -> ToolExecutionResult {
        _ = (input, sandbox)
        return ToolExecutionResult(ok: false, output: UnimplementedToolMessage.iosClient)
    }
}

struct NetworkTool: Tool {
    let definition = ToolDefinition(
        name: "request_network",
        description: "Ask the user for tool network access to an exact hostname on port 443 or 80 in the current workspace. This does not execute a command. Never assume a failed network operation granted access.",
        inputSchema: JSONSchema.object(
            [
                "justification": JSONSchema.string(
                    description: "Explain the purpose of this network access in the user\u{2019}s language."
                ),
                "target": JSONSchema.string(description: "Exact hostname:port, e.g. registry.npmjs.org:443"),
            ],
            required: ["target", "justification"],
            additionalProperties: false
        ),
        mutating: false,
        action: .network
    )

    func execute(_ input: [String: JSONValue], sandbox: RunSandbox) throws -> ToolExecutionResult {
        _ = (input, sandbox)
        return ToolExecutionResult(ok: false, output: UnimplementedToolMessage.iosClient)
    }
}

struct ExternalTool: Tool {
    let definition = ToolDefinition(
        name: "external_operation",
        description: "Request an authorized operation on the user's computer outside the workspace. Explain its concrete purpose in justification. Prefer read/import/export for files; export/import copy one file, never a directory. shell runs a bounded one-shot command with only the explicitly requested additional readPaths/writePaths; no implicit home access or network. Declare networkTargets when this same operation needs additional network access so the user receives one approval. Never retry a refused operation in the same task. User approval is determined by Host, not by you.",
        inputSchema: JSONSchema.object(
            [
                "operation": .object([
                    "type": .string("string"),
                    "enum": .array(["read", "import", "export", "shell"].map { .string($0) }),
                ]),
                "justification": JSONSchema.string(
                    description: "Brief natural-language request explaining what you need to do and why, in the user's language."
                ),
                "resourceRoot": JSONSchema.string(
                    description: "Optional explicit directory scope for repeated file operations. Approval details must show this directory. Export directory grants only create new files; overwrite is not allowed."
                ),
                "source": JSONSchema.string(),
                "destination": JSONSchema.string(),
                "overwrite": .object([
                    "type": .string("boolean"),
                    "default": .bool(false),
                ]),
                "command": JSONSchema.string(),
                "cwd": JSONSchema.string(),
                "networkTargets": JSONSchema.array(
                    items: JSONSchema.string(),
                    description: "Exact hostname:443 or hostname:80 targets needed by this operation."
                ),
                "readPaths": JSONSchema.array(items: JSONSchema.string()),
                "writePaths": JSONSchema.array(items: JSONSchema.string()),
            ],
            required: ["operation", "justification"],
            additionalProperties: false
        ),
        mutating: true,
        action: .runCommand
    )

    func execute(_ input: [String: JSONValue], sandbox: RunSandbox) throws -> ToolExecutionResult {
        _ = (input, sandbox)
        return ToolExecutionResult(ok: false, output: UnimplementedToolMessage.iosClient)
    }
}
