import NuumContracts

protocol Tool: Sendable {
    var definition: ToolDefinition { get }
    func execute(_ input: [String: JSONValue], sandbox: RunSandbox) throws -> ToolExecutionResult
}

/// Registered product tools. A nil name list means every tool. An empty list means none.
public final class ToolRegistry: Sendable {
    private let ordered: [any Tool]
    private let byName: [String: any Tool]

    init(tools: [any Tool]) {
        self.ordered = tools
        var index: [String: any Tool] = [:]
        for tool in tools {
            index[tool.definition.name] = tool
        }
        self.byName = index
    }

    func tool(named name: String) -> (any Tool)? {
        byName[name]
    }

    public func list(names: [String]? = nil) -> [ToolDefinition] {
        let all = ordered.map(\.definition)
        guard let names else { return all }
        return all.filter { names.contains($0.name) }
    }

    public static func builtin() -> ToolRegistry {
        ToolRegistry(tools: [
            ReadTool(),
            WriteTool(),
            StrReplaceTool(),
            MultiStrReplaceTool(),
            DeleteTool(),
            LsTool(),
            GlobTool(),
            GrepTool(),
            ShellTool(),
            NetworkTool(),
            ExternalTool(),
        ])
    }
}
