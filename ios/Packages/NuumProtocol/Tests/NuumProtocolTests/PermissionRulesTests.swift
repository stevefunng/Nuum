import Foundation
import Testing
import NuumProtocol

@Test func rulesDoNotAuthorizeRootCommandsCompoundScriptsOrChangedInlineCode() {
    let rule = commandRule("git status --short")
    #expect(commandMatches(rule, "git status --porcelain"))
    #expect(!commandMatches(rule, "git reset --hard"))
    #expect(!commandMatches(rule, "git status && curl evil.example"))
    #expect(!commandMatches(rule, "git status > /tmp/output"))
    let code = commandRule(#"python -c "print(1)""#)
    #expect(!commandMatches(code, #"python -c "print(2)""#))
    #expect(commandMatches(code, #"python -c "print(1)""#))
}

@Test func prefixRulesCompareArgumentsAndKeepOperatorsSeparate() {
    let rule = commandRule("gh pr view 123 --json title")
    if case .prefix(let argv) = rule {
        #expect(argv == ["gh", "pr", "view"])
    } else {
        Issue.record("expected a prefix rule")
    }
    #expect(commandMatches(rule, "gh pr view 456 --comments"))
    #expect(!commandMatches(rule, "gh pr merge 456"))
    #expect(!commandMatches(rule, "gh pr view 456; rm file"))
    #expect(!commandMatches(rule, "gh pr view 456 --web"))
}

@Test func refusalIdentityIgnoresModelProsePropertyOrderAndQuoting() throws {
    let left = permissionOperationKey(
        "external_operation",
        try ProtocolJSON.parse(#"{"operation":"shell","command":"echo 'hello'","justification":"first"}"#)
    )
    let right = permissionOperationKey(
        "external_operation",
        try ProtocolJSON.parse(
            #"{"justification":"try again","command":"echo \"hello\"","operation":"shell","readPaths":[],"writePaths":[],"networkTargets":[],"overwrite":false}"#
        )
    )
    #expect(left == right)
    let parsed = try ProtocolJSON.parse(left)
    guard case .array(let items) = parsed, items.count == 2, case .string(let name) = items[0], case .object(let fields) = items[1] else {
        Issue.record("expected [name, object]")
        return
    }
    #expect(name == "external_operation")
    #expect(!fields.contains { $0.0 == "justification" })
    let command = fields.last { $0.0 == "command" }?.1
    guard case .array(let words) = command, words.count > 1, case .string(let word) = words[1] else {
        Issue.record("expected command words")
        return
    }
    #expect(word == "hello")
}

@Test func queryGrammarsAcceptOnlyTheirExplicitParameters() {
    let families = [
        [
            "git log --oneline -n 10",
            "git log --graph --max-count=20",
            "git log --output=/tmp/log",
            "git log -p",
            "git log -n --all",
        ],
        [
            "git diff --no-ext-diff --no-textconv --stat",
            "git diff --no-ext-diff --no-textconv --cached --name-only",
            "git diff --stat",
            "git diff --no-ext-diff --no-textconv --ext-diff",
            "git diff --no-ext-diff --no-textconv --output=/tmp/diff",
        ],
        [
            "gh issue view 1",
            "gh issue view 2 --comments --json title",
            "gh issue close 2",
            "gh issue view 2 --web",
        ],
        [
            "gh pr list --state open --limit 10",
            "gh pr list --state merged --limit 20 --json title",
            "gh pr list --web",
            "gh pr list --limit --web",
        ],
        [
            "gh issue list --state open",
            "gh issue list --state closed --limit 20",
            "gh issue list --state merged",
            "gh issue list --template evil",
        ],
        [
            "gh run list --limit 10",
            "gh run list --limit 20 --json status",
            "gh run rerun 1",
            "gh run list --limit 0",
        ],
        [
            "gh run view 1",
            "gh run view 2 --verbose --json status",
            "gh run view 2 --web",
            "gh run view 2 --log",
        ],
    ]
    for family in families {
        let initial = family[0]
        let variation = family[1]
        let rule = commandRule(initial)
        if case .prefix = rule {} else { Issue.record("\(initial) should be a prefix rule") }
        #expect(commandMatches(rule, variation))
        let rejected = Array(family.dropFirst(2)) + [
            "\(variation) && rm file",
            "\(variation) > out",
            "\(variation) --unknown",
            "\(variation) $(echo hi)",
        ]
        for command in rejected {
            #expect(!commandMatches(rule, command))
        }
        for other in families where other[0] != initial {
            #expect(!commandMatches(rule, other[0]))
        }
    }
}

@Test func grantsDoNotWidenResourceNetworkOrFingerprintBoundaries() {
    let grant = ExternalGrant(
        environment: "local",
        workspaceId: "w",
        operation: .shell,
        readPaths: ["/reports"],
        writePaths: [],
        overwrite: false,
        cwd: "/work",
        command: commandRule("git log --oneline -n 10"),
        networkTargets: [],
        fingerprints: .object([("/usr/bin/git", .string("hash"))])
    )
    let next = ExternalGrant(
        environment: grant.environment,
        workspaceId: grant.workspaceId,
        operation: grant.operation,
        readPaths: grant.readPaths,
        writePaths: grant.writePaths,
        overwrite: grant.overwrite,
        cwd: grant.cwd,
        command: commandRule("git log --graph -n 20"),
        networkTargets: grant.networkTargets,
        fingerprints: grant.fingerprints
    )
    #expect(externalGrantCovers(grant, next))
    #expect(!externalGrantCovers(grant, replacing(next, workspaceId: "other")))
    #expect(!externalGrantCovers(grant, replacing(next, cwd: "/other")))
    #expect(!externalGrantCovers(grant, replacing(next, readPaths: ["/secret"])))
    #expect(!externalGrantCovers(grant, replacing(next, writePaths: ["/reports"])))
    #expect(!externalGrantCovers(grant, replacing(next, networkTargets: ["example.com:443"])))
    #expect(!externalGrantCovers(grant, replacing(next, fingerprints: .object([("/usr/bin/git", .string("changed"))]))))
}

@Test func queryExpansionDoesNotWidenSavedExactRulesOrCompoundStructure() {
    #expect(!commandMatches(.exact(command: "git log --oneline -n 10"), "git log --graph -n 20"))
    let chain = commandRule("git log --oneline -n 10 && gh issue list --state open")
    #expect(commandMatches(chain, "git log --graph -n 20 && gh issue list --state closed"))
    #expect(!commandMatches(chain, "git log --graph -n 20 || gh issue list --state closed"))
    let exact = [
        "git -c alias.log=evil log",
        "gh alias run",
        "gh issue view 1 2",
        "gh run view",
        "git log --max-count=0",
        "git log --max-count=10000",
        "git log --max-count=-1",
        "git log --max-count=10x",
        "git log -n",
        "gh issue view 1 --repo=--web",
    ]
    for command in exact {
        if case .exact = commandRule(command) {} else { Issue.record("\(command) should stay exact") }
    }
}

private func replacing(
    _ grant: ExternalGrant,
    workspaceId: String? = nil,
    cwd: String? = nil,
    readPaths: [String]? = nil,
    writePaths: [String]? = nil,
    networkTargets: [String]? = nil,
    fingerprints: JSONValue? = nil
) -> ExternalGrant {
    ExternalGrant(
        environment: grant.environment,
        workspaceId: workspaceId ?? grant.workspaceId,
        operation: grant.operation,
        readPaths: readPaths ?? grant.readPaths,
        writePaths: writePaths ?? grant.writePaths,
        overwrite: grant.overwrite,
        cwd: cwd ?? grant.cwd,
        command: grant.command,
        networkTargets: networkTargets ?? grant.networkTargets,
        fingerprints: fingerprints ?? grant.fingerprints
    )
}

@Test func linearCompoundRulesCheckEveryCommandAndPreserveOperators() {
    let rule = commandRule("git status --short && gh pr view 123")
    if case .compound = rule {} else { Issue.record("expected a compound rule") }
    #expect(commandMatches(rule, "git status --branch && gh pr view 456"))
    #expect(!commandMatches(rule, "git status --branch && gh pr merge 456"))
    #expect(!commandMatches(rule, "git status --short || gh pr view 123"))
    #expect(!commandMatches(rule, "git status --short && gh pr view 123 && rm file"))
    #expect(staticShellWords("echo ok\nrm file") == nil)
}
