import NuumContracts
import Testing
@testable import NuumTools

@Test func builtinOrderMatchesTheToolSurface() {
    let names = ToolRegistry.builtin().list().map(\.name)
    #expect(names == [
        "read",
        "write",
        "str_replace",
        "multi_str_replace",
        "delete",
        "ls",
        "glob",
        "grep",
        "shell",
        "request_network",
        "external_operation",
    ])
    let byName = Dictionary(uniqueKeysWithValues: ToolRegistry.builtin().list().map { ($0.name, $0) })
    #expect(byName["shell"]?.mutating == true)
    #expect(byName["shell"]?.action == .runCommand)
    #expect(byName["request_network"]?.mutating == false)
    #expect(byName["request_network"]?.action == .network)
    #expect(byName["external_operation"]?.action == .runCommand)
    #expect(byName["read"]?.action == .readFile)
    #expect(byName["grep"]?.mutating == false)
    #expect(byName["grep"]?.description.contains("no external search program") == true)
}

@Test func noFilterMeansEveryToolAndAnEmptyFilterMeansNone() {
    let registry = ToolRegistry(tools: [StubTool(name: "read"), StubTool(name: "write")])
    #expect(registry.list().map(\.name) == ["read", "write"])
    #expect(registry.list(names: []).isEmpty)
}

@Test func aFilterKeepsRegistryOrderAndDropsUnknownNames() {
    let registry = ToolRegistry(tools: [
        StubTool(name: "read"),
        StubTool(name: "write"),
        StubTool(name: "shell"),
    ])
    #expect(registry.list(names: ["shell", "ghost", "read"]).map(\.name) == ["read", "shell"])
}

@Test func backendListUsesTheSameEmptyVersusAbsentRule() {
    let backend = LocalToolBackend(files: MemoryToolFileSystem())
    #expect(backend.definitions().count == 11)
    #expect(backend.definitions().map(\.name) == backend.list().map(\.name))
    #expect(backend.list(names: []).isEmpty)
}

private struct StubTool: Tool {
    var definition: ToolDefinition

    init(name: String) {
        definition = ToolDefinition(
            name: name,
            description: name,
            inputSchema: ["type": .string("object")],
            mutating: false
        )
    }

    func execute(_ input: [String: JSONValue], sandbox: RunSandbox) throws -> ToolExecutionResult {
        _ = (input, sandbox)
        return ToolExecutionResult(ok: true, output: definition.name)
    }
}
