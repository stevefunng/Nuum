import Foundation
import Testing
import NuumProtocol

private func thrownMessage(_ body: () throws -> Void) -> String? {
    do {
        try body()
        return nil
    } catch let error as ProtocolParseException {
        return error.message
    } catch {
        return String(describing: error)
    }
}

@Test func providerFallbackOrder() {
    let deepseek = ModelRef(provider: .deepseek, model: "deepseek-chat")
    let openai = ModelRef(provider: .openai, model: "gpt-4o")
    let anthropic = ModelRef(provider: .anthropic, model: "claude-sonnet-4-20250514")
    #expect(providerFallback == [.deepseek, .openai, .anthropic])
    #expect(defaultSettings.defaultModel == deepseek)
    #expect(defaultSettings.defaultToolPermission == .ask)

    let all = Secrets(openaiApiKey: "o", anthropicApiKey: "a", deepseekApiKey: "d")
    #expect(secretForProvider(all, .openai) == "o")
    #expect(secretForProvider(all, .anthropic) == "a")
    #expect(secretForProvider(all, .deepseek) == "d")
    #expect(resolveAvailableModel(all) == deepseek)
    #expect(resolveAvailableModel(Secrets(openaiApiKey: "o", anthropicApiKey: "a")) == openai)
    #expect(resolveAvailableModel(Secrets(anthropicApiKey: "a")) == anthropic)
    #expect(resolveAvailableModel(Secrets()) == nil)
    #expect(resolveAvailableModel(Secrets(deepseekApiKey: "")) == nil)

    let preferred = ModelRef(provider: .deepseek, model: "deepseek-reasoner")
    #expect(resolveAvailableModel(Secrets(deepseekApiKey: "d"), preferred: preferred) == preferred)
    #expect(resolveAvailableModel(Secrets(deepseekApiKey: "d"), preferred: ModelRef(provider: .openai, model: "gpt-4o")) == deepseek)
    let customOpenAI = ModelRef(provider: .openai, model: "gpt-4o-mini")
    #expect(resolveAvailableModel(Secrets(openaiApiKey: "o", deepseekApiKey: "d"), preferred: customOpenAI) == customOpenAI)
    let secret = Secrets(openaiApiKey: "sk-test-secret")
    #expect(!String(describing: secret).contains("sk-test-secret"))
    #expect(!String(reflecting: secret).contains("sk-test-secret"))
}

@Test func attachmentLimits() throws {
    #expect(maxAttachments == 5)
    #expect(maxAttachmentBytes == 10 * 1024 * 1024)
    #expect(maxAttachmentTotalBytes == 20 * 1024 * 1024)
    #expect(maxAttachmentBase64Chars == ((maxAttachmentBytes + 2) / 3) * 4)
    #expect(attachmentLimitError([1024, 1024]) == nil)
    #expect(attachmentLimitError(Array(repeating: Int64(maxAttachmentBytes) / 5, count: 5)) == nil)
    #expect(attachmentLimitError(Array(repeating: 1, count: 6)) == attachmentCountMessage)
    #expect(attachmentLimitError([Int64(maxAttachmentBytes) + 1]) == attachmentSizeMessage)
    #expect(attachmentLimitError([10 * 1024 * 1024, 10 * 1024 * 1024]) == nil)
    #expect(attachmentLimitError([7 * 1024 * 1024, 7 * 1024 * 1024, 7 * 1024 * 1024]) == attachmentTotalMessage)
    #expect(attachmentLimitError(Array(repeating: Int64(maxAttachmentBytes) + 1, count: 6)) == attachmentCountMessage)
    try validateAttachmentUpload(AttachmentUpload(name: "note.txt", mimeType: "text/plain", data: "YQ=="))
    let malformed = thrownMessage {
        try validateAttachmentUpload(AttachmentUpload(name: "note.txt", mimeType: "text/plain", data: "not base64"))
    }
    #expect(malformed?.contains("data") == true)
    let badLength = thrownMessage {
        try validateAttachmentUpload(AttachmentUpload(name: "note.txt", mimeType: "text/plain", data: "YQ="))
    }
    #expect(badLength?.contains("Invalid base64 length") == true)
    #expect(supportsImageInput(ModelRef(provider: .deepseek, model: "deepseek-chat")) == false)
    #expect(supportsImageInput(ModelRef(provider: .openai, model: "custom-model")) == false)
    #expect(supportsImageInput(ModelRef(provider: .openai, model: "o3-mini")) == false)
    #expect(supportsImageInput(ModelRef(provider: .openai, model: "gpt-4o")) == true)
    #expect(supportsImageInput(ModelRef(provider: .anthropic, model: "claude-sonnet-4-20250514")) == true)
}

@Test func sidebarPinsGroupsAndMembersMustBeUnique() throws {
    let valid = SidebarOrganization(
        pinnedAgentIds: ["a"],
        sections: [SidebarSection(id: "design", name: "  Design  ", agentIds: ["b"])]
    )
    #expect(sidebarUniquenessError(valid) == nil)
    #expect(try validateSidebar(valid).sections[0].name == "Design")
    #expect(sidebarUniquenessError(SidebarOrganization(pinnedAgentIds: ["a", "a"], sections: valid.sections)) == sidebarUniquenessMessage)
    #expect(
        sidebarUniquenessError(
            SidebarOrganization(sections: [
                SidebarSection(id: "design", name: "Design", agentIds: ["b"]),
                SidebarSection(id: "design", name: "Other", agentIds: ["c"]),
            ])
        ) == sidebarUniquenessMessage
    )
    #expect(
        sidebarUniquenessError(
            SidebarOrganization(sections: [
                SidebarSection(id: "design", name: "Design", agentIds: ["b"]),
                SidebarSection(id: "research", name: "Research", agentIds: ["b"]),
            ])
        ) == sidebarUniquenessMessage
    )
    let duplicate = thrownMessage {
        _ = try validateSidebar(SidebarOrganization(pinnedAgentIds: ["a", "a"], sections: valid.sections))
    }
    #expect(duplicate?.contains(sidebarUniquenessMessage) == true)
}

@Test func taskStatusEnumMatchesTheMacWireValues() throws {
    #expect(workTaskStates == ["proposed", "ready", "in_progress", "blocked", "review", "done", "cancelled"])
    let task = """
    {
      "id": "task-1",
      "title": "Verify package",
      "description": "Run release checks",
      "acceptanceCriteria": ["all checks pass"],
      "state": "review",
      "assigneeIds": ["agent-1"],
      "dependencyIds": [],
      "priority": "normal",
      "revision": 3,
      "deliverables": [],
      "createdAt": 1,
      "updatedAt": 2
    }
    """
    let parsed = try ProtocolJSON.decode(WorkTask.self, from: task)
    #expect(parsed.state == .review)
    #expect(parsed.revision == 3)
    #expect(thrownMessage { _ = try ProtocolJSON.decode(WorkTask.self, from: task.replacingOccurrences(of: "review", with: "finished")) } != nil)
    let catalog = try ProtocolJSON.decode(
        WorkCatalog.self,
        from: """
        {"revision":2,"entries":[{
          "id":"knowledge-1","kind":"knowledge","name":"Product docs",
          "description":"Local design documents","enabled":true,
          "roots":["/tmp/launch/docs"],"readOnly":true
        }]}
        """
    )
    if case .knowledge(_, _, _, _, _, let readOnly) = catalog.entries[0] {
        #expect(readOnly)
    } else {
        Issue.record("expected a knowledge entry")
    }
    #expect(thrownMessage {
        _ = try ProtocolJSON.decode(
            WorkCatalogEntry.self,
            from: #"{"id":"k","kind":"knowledge","name":"Docs","description":"","enabled":true,"roots":["/tmp"],"readOnly":false}"#
        )
    } != nil)
    let membership = try ProtocolJSON.decode(WorkMembership.self, from: #"{"revision":0,"binding":null}"#)
    #expect(membership.binding == nil)
    #expect(ProtocolJSON.encode(membership).contains("\"binding\":null"))
    let posted = try ProtocolJSON.decode(
        WorkEvent.self,
        from: """
        {"type":"chat.posted","id":"event-1","workId":"work-1","seq":4,"createdAt":100,
         "actor":{"kind":"user","id":"local-user"},"messageId":"message-1",
         "body":"Please review task one","mentionedAgentIds":["agent-1"]}
        """
    )
    if case .chatPosted(let chat) = posted {
        #expect(chat.seq == 4)
    } else {
        Issue.record("expected chat.posted")
    }
}

@Test func actionsAvailableCanOnlyBeFalse() throws {
    let snapshot = try ProactiveSnapshot(defaultAgentId: nil, agents: [], availableSourceIds: [], actionsAvailable: false)
    let json = ProtocolJSON.encode(snapshot)
    #expect(json.contains("\"actionsAvailable\":false"))
    let roundTrip = try ProtocolJSON.decode(ProactiveSnapshot.self, from: json)
    #expect(roundTrip.actionsAvailable == false)
    let rejected = thrownMessage {
        _ = try ProtocolJSON.decode(ProactiveSnapshot.self, from: json.replacingOccurrences(of: "\"actionsAvailable\":false", with: "\"actionsAvailable\":true"))
    }
    #expect(rejected?.contains("false") == true)
    #expect(thrownMessage {
        _ = try ProactiveSnapshot(defaultAgentId: nil, agents: [], availableSourceIds: [], actionsAvailable: true)
    } != nil)
    #expect(thrownMessage {
        _ = try ProtocolJSON.decode(
            ProactiveSnapshot.self,
            from: #"{"defaultAgentId":null,"agents":[],"availableSourceIds":[]}"#
        )
    } != nil)
    let duplicate = thrownMessage {
        try validateProactivePolicy(ProactivePolicy(revision: 1, sourceIds: ["calendar", "calendar"]))
    }
    #expect(duplicate?.contains(duplicateContextSource) == true)
    #expect(proactiveIntervalMinMs == 60_000)
    #expect(proactiveIntervalMaxMs == 3_600_000)
    #expect(proactiveIntervalDefaultMs == 300_000)
    let data = try JSONEncoder().encode(snapshot)
    let encoded = String(decoding: data, as: UTF8.self)
    #expect(encoded.contains("\"actionsAvailable\":false"))
    let flipped = Data(encoded.replacingOccurrences(of: "\"actionsAvailable\":false", with: "\"actionsAvailable\":true").utf8)
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(ProactiveSnapshot.self, from: flipped)
    }
    let decoded = try JSONDecoder().decode(ProactiveSnapshot.self, from: data)
    #expect(decoded.actionsAvailable == false)
}

@Test func imageAdds8192TokensAndDoesNotCountItsBytes() {
    let message = ChatMessage(id: "m", role: .user, content: "hi", seq: 1, createdAt: 1)
    let payload = String(repeating: "A", count: 10_000)
    let withImage = ChatMessage(
        id: message.id,
        role: message.role,
        content: message.content,
        seq: message.seq,
        createdAt: message.createdAt,
        images: [ModelImage(mimeType: "image/png", data: payload)]
    )
    let withTwo = ChatMessage(
        id: message.id,
        role: message.role,
        content: message.content,
        seq: message.seq,
        createdAt: message.createdAt,
        images: [ModelImage(mimeType: "image/png", data: payload), ModelImage(mimeType: "image/jpeg", data: "BBBB")]
    )
    #expect(estimateModelTokens([withImage]) == estimateModelTokens([message]) + 8192)
    #expect(estimateModelTokens([withTwo]) == estimateModelTokens([message]) + 16384)
    let cjk = ChatMessage(
        id: message.id,
        role: message.role,
        content: message.content + "你",
        seq: message.seq,
        createdAt: message.createdAt
    )
    #expect(estimateModelTokens([cjk]) == estimateModelTokens([message]) + 2)
}

@Test func sendMessageKeepsTheModelFacingSentences() throws {
    let misplaced = thrownMessage {
        _ = try parseSendMessage(try ProtocolJSON.parse(#"{"type":"text","content":"hi","path":"/tmp/a"}"#))
    }
    #expect(
        misplaced
            == "path: path is only valid with type:attachment, not type:text — it would be silently dropped. Nothing was sent. Re-send as separate SendMessage calls, one per type."
    )
    let both = thrownMessage {
        _ = try parseSendMessage(try ProtocolJSON.parse(#"{"type":"text","path":"/tmp/a"}"#))
    }
    #expect(both?.hasPrefix("path: path is only valid with type:attachment") == true)
    #expect(both?.contains("content: content is required when type is text. Nothing was sent.") == true)
    let parse = ProtocolParseException(
        ["path"],
        "path is only valid with type:attachment, not type:text — it would be silently dropped. Nothing was sent. Re-send as separate SendMessage calls, one per type."
    )
    #expect(toolArgumentError(toolName: "SendMessage", error: parse).hasPrefix("SendMessage: invalid arguments — "))
    let missing = thrownMessage {
        _ = try parseSendMessage(try ProtocolJSON.parse(#"{"type":"text"}"#))
    }
    #expect(missing == "content: content is required when type is text. Nothing was sent.")
    let missingFile = thrownMessage {
        _ = try parseSendMessage(try ProtocolJSON.parse(#"{"type":"attachment"}"#))
    }
    #expect(missingFile == "path: path is required when type is attachment. Nothing was sent.")
    let missingWidget = thrownMessage {
        _ = try parseSendMessage(try ProtocolJSON.parse(#"{"type":"widget"}"#))
    }
    #expect(missingWidget == "widget: widget is required when type is widget: an object with prompt and options. Nothing was sent.")
    let sent = try parseSendMessage(try ProtocolJSON.parse(#"{"type":"text","content":"hi"}"#))
    #expect(sent == .text(content: "hi", images: nil))
    let legacy = try parseOutboundMessage(try ProtocolJSON.parse(#"{"type":"text","text":"hi","images":["/tmp/a.png",{"path":"/tmp/b.png","alt":"b"}]}"#))
    #expect(legacy == .text(content: "hi", images: [OutboundImage(path: "/tmp/a.png"), OutboundImage(path: "/tmp/b.png", alt: "b")]))
}

@Test func errorCodesMatchTheMacNumbers() {
    #expect(KernelErrorCode.internal == 1000)
    #expect(KernelErrorCode.turnBusy == 1002)
    #expect(KernelErrorCode.cancelled == 1003)
    #expect(KernelErrorCode.model == 1004)
    #expect(KernelErrorCode.tool == 1005)
    #expect(KernelErrorCode.sandbox == 1006)
    #expect(KernelErrorCode.invalid == 1007)
    #expect(HostErrorCode.agentNotFound == 2001)
    #expect(HostErrorCode.noAPIKey == 2004)
    #expect(HostErrorCode.kernelDown == 2008)
    #expect(HostErrorCode.workForbidden == 2012)
    #expect(DesktopErrorCode.secretStore == 3001)
    #expect(DesktopErrorCode.folderPick == 3002)
    #expect(DesktopErrorCode.window == 3003)
    let error = RpcError(code: KernelErrorCode.model, message: "provider failed")
    #expect(error.code == 1004)
    #expect(error.message == "provider failed")
}

@Test func transcriptProjectionKeepsDeliveredMessagesAndStripsRoomPrompts() throws {
    let user = try parseTranscriptLine(try ProtocolJSON.parse(#"{"type":"user","id":"u","seq":1,"createdAt":1,"text":"x"}"#))
    #expect(user == .user(id: "u", seq: 1, createdAt: 1, text: "x", attachments: nil, widgetAnswerTo: nil))
    let legacyUser = try parseTranscriptLine(try ProtocolJSON.parse(#"{"id":"u1","role":"user","content":"hello","seq":1,"createdAt":10}"#))
    #expect(legacyUser == .user(id: "u1", seq: 1, createdAt: 10, text: "hello", attachments: nil, widgetAnswerTo: nil))
    #expect(eventFromChatMessage(ChatMessage(id: "sys", role: .system, content: "hidden", seq: 0, createdAt: 0)) == nil)
    let view = projectAgent([
        .user(id: "u1", seq: 1, createdAt: 1, text: "say hi", attachments: nil, widgetAnswerTo: nil),
        .assistant(id: "a1", seq: 2, createdAt: 2, parts: [
            .text(text: "draft: maybe say hello"),
            .toolCall(id: "c1", executionId: nil, name: "SendMessage", arguments: try ProtocolJSON.parse(#"{"type":"text","content":"hi"}"#)),
        ]),
        .message(
            id: "m1",
            seq: 3,
            createdAt: 3,
            assistantId: "a1",
            toolCallId: "c1",
            payload: .text(content: "hi", images: nil)
        ),
    ])
    if case .user = view.blocks[0] {} else { Issue.record("expected a user block") }
    if case .message = view.blocks[1] {} else { Issue.record("expected a delivered message") }
    let room = projectAgent([
        .wake(
            id: "w",
            seq: 1,
            createdAt: 1,
            source: .work(workId: "room", workName: "Design", bridgeId: "bridge", taskId: nil, roomInput: nil),
            text: "Trigger: internal instructions",
            hops: 0
        ),
    ])
    if case .notice(_, _, let text) = room.blocks[0] {
        #expect(text.contains("Design"))
        #expect(!text.contains("Trigger:"))
    } else {
        Issue.record("expected a room notice")
    }
    #expect(tryParseTranscriptLine("{") == nil)
}

@Test func networkTargetsOnlyAllowHostPorts80And443() {
    #expect(isNetworkTarget("example.com:443"))
    #expect(isNetworkTarget("example.com:80"))
    #expect(!isNetworkTarget("example.com:22"))
    #expect(!isNetworkTarget("http://example.com:443"))
    #expect(!isNetworkTarget("example.com"))
}

@Test func rolledAvatarStaysInsideThePublishedEditionSet() {
    var random = SplitMix64(seed: 7)
    let roll = rollAgentAvatar(using: &random)
    #expect(agentAvatarColors.map(\.id).contains(roll.color))
    #expect(agentAvatarShapes.contains(roll.shape))
    #expect(agentAvatarMaterials.contains(roll.material))
    #expect(resolveAgentAvatarMaterial(requested: "aurora") == "aurora")
    #expect(resolveAgentAvatarMaterial(requested: "unknown") == "plush")
}

@Test func deniedCommandPatternsArePreserved() {
    let deny = [
        #"\brm\s+(?:-[a-zA-Z]*r[a-zA-Z]*f|-[a-zA-Z]*f[a-zA-Z]*r)\s+(?:/|~|\$HOME)(?:\s|$)"#,
        #"\bmkfs\b"#,
        #"\bdd\s+if="#,
        #":\(\)\s*\{\s*:\|\:&\s*\};:"#,
    ]
    #expect(deny.contains { containsMatch($0, "rm -rf /") })
    #expect(deny.contains { containsMatch($0, "rm -fr ~") })
    #expect(deny.contains { containsMatch($0, "rm -rf $HOME") })
    #expect(deny.contains { containsMatch($0, "mkfs.ext4 /dev/sda") })
    #expect(deny.contains { containsMatch($0, "dd if=/dev/zero of=disk") })
    #expect(deny.contains { containsMatch($0, ":(){ :|:& };:") })
    #expect(!deny.contains { containsMatch($0, "rm file.txt") })
    #expect(!deny.contains { containsMatch($0, "echo hello") })
}

private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z &>> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z &>> 27)) &* 0x94D049BB133111EB
        return z ^ (z &>> 31)
    }
}

private func containsMatch(_ pattern: String, _ text: String) -> Bool {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
    let range = NSRange(text.startIndex..., in: text)
    return regex.firstMatch(in: text, range: range) != nil
}
