package com.nuum.tools

import com.nuum.contracts.LocalToolAction
import com.nuum.contracts.ToolDefinition
import com.nuum.contracts.ToolExecutionResult

internal object ShellTool : Tool {
    override val definition = ToolDefinition(
        name = "shell",
        description = "Run a command in this agent's persistent bash, or inspect a background job by shell_id.",
        inputSchema = jsonMap(
            "type" to "object",
            "properties" to mapOf(
                "command" to mapOf("type" to "string"),
                "working_directory" to mapOf("type" to "string"),
                "block_until_ms" to mapOf("type" to "integer", "minimum" to 0, "default" to 30_000),
                "shell_id" to mapOf("type" to "string")
            ),
            "oneOf" to listOf(
                mapOf("required" to listOf("command")),
                mapOf("required" to listOf("shell_id"))
            )
        ),
        mutating = true,
        action = LocalToolAction.RUN_COMMAND
    )

    override suspend fun execute(input: Map<String, Any?>, sandbox: RunSandbox): ToolExecutionResult =
        ToolExecutionResult(ok = false, output = POC_NOT_IMPLEMENTED)
}

internal object NetworkTool : Tool {
    override val definition = ToolDefinition(
        name = "request_network",
        description = "Ask the user for tool network access to an exact hostname on port 443 or 80 in the current workspace. This does not execute a command. Never assume a failed network operation granted access.",
        inputSchema = jsonMap(
            "type" to "object",
            "properties" to mapOf(
                "justification" to mapOf(
                    "type" to "string",
                    "description" to "Explain the purpose of this network access in the user’s language."
                ),
                "target" to mapOf(
                    "type" to "string",
                    "description" to "Exact hostname:port, e.g. registry.npmjs.org:443"
                )
            ),
            "required" to listOf("target", "justification"),
            "additionalProperties" to false
        ),
        mutating = false,
        action = LocalToolAction.NETWORK
    )

    override suspend fun execute(input: Map<String, Any?>, sandbox: RunSandbox): ToolExecutionResult =
        ToolExecutionResult(ok = false, output = POC_NOT_IMPLEMENTED)
}

internal object ExternalTool : Tool {
    override val definition = ToolDefinition(
        name = "external_operation",
        description = "Request an authorized operation on the user's computer outside the workspace. Explain its concrete purpose in justification. Prefer read/import/export for files; export/import copy one file, never a directory. shell runs a bounded one-shot command with only the explicitly requested additional readPaths/writePaths; no implicit home access or network. Declare networkTargets when this same operation needs additional network access so the user receives one approval. Never retry a refused operation in the same task. User approval is determined by Host, not by you.",
        inputSchema = jsonMap(
            "type" to "object",
            "properties" to mapOf(
                "operation" to mapOf("type" to "string", "enum" to listOf("read", "import", "export", "shell")),
                "justification" to mapOf(
                    "type" to "string",
                    "description" to "Brief natural-language request explaining what you need to do and why, in the user's language."
                ),
                "resourceRoot" to mapOf(
                    "type" to "string",
                    "description" to "Optional explicit directory scope for repeated file operations. Approval details must show this directory. Export directory grants only create new files; overwrite is not allowed."
                ),
                "source" to mapOf("type" to "string"),
                "destination" to mapOf("type" to "string"),
                "overwrite" to mapOf("type" to "boolean", "default" to false),
                "command" to mapOf("type" to "string"),
                "cwd" to mapOf("type" to "string"),
                "networkTargets" to mapOf(
                    "type" to "array",
                    "items" to mapOf("type" to "string"),
                    "description" to "Exact hostname:443 or hostname:80 targets needed by this operation."
                ),
                "readPaths" to mapOf("type" to "array", "items" to mapOf("type" to "string")),
                "writePaths" to mapOf("type" to "array", "items" to mapOf("type" to "string"))
            ),
            "required" to listOf("operation", "justification"),
            "additionalProperties" to false
        ),
        mutating = true,
        action = LocalToolAction.RUN_COMMAND
    )

    override suspend fun execute(input: Map<String, Any?>, sandbox: RunSandbox): ToolExecutionResult =
        ToolExecutionResult(ok = false, output = POC_NOT_IMPLEMENTED)
}
