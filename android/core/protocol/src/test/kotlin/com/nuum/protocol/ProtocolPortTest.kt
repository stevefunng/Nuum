package com.nuum.protocol

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class ProtocolPortTest {
    @Test
    fun providerFallbackOrder() {
        val deepseek = ModelRef(ProviderId.DEEPSEEK, "deepseek-chat")
        val openai = ModelRef(ProviderId.OPENAI, "gpt-4o")
        val anthropic = ModelRef(ProviderId.ANTHROPIC, "claude-sonnet-4-20250514")
        assertEquals(listOf(ProviderId.DEEPSEEK, ProviderId.OPENAI, ProviderId.ANTHROPIC), PROVIDER_FALLBACK)
        assertEquals(deepseek, DEFAULT_SETTINGS.defaultModel)
        assertEquals(ToolPermission.ASK, DEFAULT_SETTINGS.defaultToolPermission)

        val all = Secrets(openaiApiKey = "o", anthropicApiKey = "a", deepseekApiKey = "d")
        assertEquals("o", secretForProvider(all, ProviderId.OPENAI))
        assertEquals("a", secretForProvider(all, ProviderId.ANTHROPIC))
        assertEquals("d", secretForProvider(all, ProviderId.DEEPSEEK))
        assertEquals(deepseek, resolveAvailableModel(all))
        assertEquals(openai, resolveAvailableModel(Secrets(openaiApiKey = "o", anthropicApiKey = "a")))
        assertEquals(anthropic, resolveAvailableModel(Secrets(anthropicApiKey = "a")))
        assertNull(resolveAvailableModel(Secrets()))
        assertNull(resolveAvailableModel(Secrets(deepseekApiKey = "")))

        val preferred = ModelRef(ProviderId.DEEPSEEK, "deepseek-reasoner")
        assertEquals(preferred, resolveAvailableModel(Secrets(deepseekApiKey = "d"), preferred))
        assertEquals(
            deepseek,
            resolveAvailableModel(Secrets(deepseekApiKey = "d"), ModelRef(ProviderId.OPENAI, "gpt-4o"))
        )
        val customOpenAi = ModelRef(ProviderId.OPENAI, "gpt-4o-mini")
        assertEquals(customOpenAi, resolveAvailableModel(Secrets(openaiApiKey = "o", deepseekApiKey = "d"), customOpenAi))
    }

    @Test
    fun attachmentLimits() {
        assertEquals(5, MAX_ATTACHMENTS)
        assertEquals(10 * 1024 * 1024, MAX_ATTACHMENT_BYTES)
        assertEquals(20 * 1024 * 1024, MAX_ATTACHMENT_TOTAL_BYTES)
        assertEquals(((MAX_ATTACHMENT_BYTES + 2) / 3) * 4, MAX_ATTACHMENT_BASE64_CHARS)
        assertNull(attachmentLimitError(listOf(1024L, 1024L)))
        assertNull(attachmentLimitError(List(5) { MAX_ATTACHMENT_BYTES.toLong() / 5 }))
        assertEquals(ATTACHMENT_COUNT_MESSAGE, attachmentLimitError(List(6) { 1L }))
        assertEquals(ATTACHMENT_SIZE_MESSAGE, attachmentLimitError(listOf(MAX_ATTACHMENT_BYTES + 1L)))
        assertNull(attachmentLimitError(listOf(10L * 1024 * 1024, 10L * 1024 * 1024)))
        assertEquals(
            ATTACHMENT_TOTAL_MESSAGE,
            attachmentLimitError(listOf(7L * 1024 * 1024, 7L * 1024 * 1024, 7L * 1024 * 1024))
        )
        assertEquals(
            ATTACHMENT_COUNT_MESSAGE,
            attachmentLimitError(List(6) { MAX_ATTACHMENT_BYTES + 1L })
        )
        validateAttachmentUpload(AttachmentUpload("note.txt", "text/plain", "YQ=="))
        val malformed = assertThrows(ProtocolParseException::class.java) {
            validateAttachmentUpload(AttachmentUpload("note.txt", "text/plain", "not base64"))
        }
        assertTrue(malformed.message!!.contains("data"))
        val badLength = assertThrows(ProtocolParseException::class.java) {
            validateAttachmentUpload(AttachmentUpload("note.txt", "text/plain", "YQ="))
        }
        assertTrue(badLength.message!!.contains("Invalid base64 length"))
        assertFalse(supportsImageInput(ModelRef(ProviderId.DEEPSEEK, "deepseek-chat")))
        assertFalse(supportsImageInput(ModelRef(ProviderId.OPENAI, "custom-model")))
        assertFalse(supportsImageInput(ModelRef(ProviderId.OPENAI, "o3-mini")))
        assertTrue(supportsImageInput(ModelRef(ProviderId.OPENAI, "gpt-4o")))
        assertTrue(supportsImageInput(ModelRef(ProviderId.ANTHROPIC, "claude-sonnet-4-20250514")))
    }

    @Test
    fun sidebarPinsGroupsAndMembersMustBeUnique() {
        val valid = SidebarOrganization(
            pinnedAgentIds = listOf("a"),
            sections = listOf(SidebarSection("design", "  Design  ", listOf("b")))
        )
        assertNull(sidebarUniquenessError(valid))
        assertEquals("Design", validateSidebar(valid).sections.single().name)
        assertEquals(
            SIDEBAR_UNIQUENESS_MESSAGE,
            sidebarUniquenessError(valid.copy(pinnedAgentIds = listOf("a", "a")))
        )
        assertEquals(
            SIDEBAR_UNIQUENESS_MESSAGE,
            sidebarUniquenessError(
                SidebarOrganization(
                    sections = listOf(
                        SidebarSection("design", "Design", listOf("b")),
                        SidebarSection("design", "Other", listOf("c"))
                    )
                )
            )
        )
        assertEquals(
            SIDEBAR_UNIQUENESS_MESSAGE,
            sidebarUniquenessError(
                SidebarOrganization(
                    sections = listOf(
                        SidebarSection("design", "Design", listOf("b")),
                        SidebarSection("research", "Research", listOf("b"))
                    )
                )
            )
        )
        val duplicate = assertThrows(ProtocolParseException::class.java) {
            validateSidebar(valid.copy(pinnedAgentIds = listOf("a", "a")))
        }
        assertTrue(duplicate.message!!.contains(SIDEBAR_UNIQUENESS_MESSAGE))
    }

    @Test
    fun taskStatusEnumMatchesTheMacWireValues() {
        assertEquals(
            WORK_TASK_STATES,
            WorkTaskState.entries.map { ProtocolJson.encodeToString(WorkTaskState.serializer(), it).trim('"') }
        )
        val task = """
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
        """.trimIndent()
        val parsed = ProtocolJson.decodeFromString(WorkTask.serializer(), task)
        assertEquals(WorkTaskState.REVIEW, parsed.state)
        assertEquals(3, parsed.revision)
        assertThrows(Exception::class.java) {
            ProtocolJson.decodeFromString(WorkTask.serializer(), task.replace("review", "finished"))
        }
        val catalog = ProtocolJson.decodeFromString(
            WorkCatalog.serializer(),
            """
            {"revision":2,"entries":[{
              "id":"knowledge-1","kind":"knowledge","name":"Product docs",
              "description":"Local design documents","enabled":true,
              "roots":["/tmp/launch/docs"],"readOnly":true
            }]}
            """.trimIndent()
        )
        assertTrue(catalog.entries.single() is WorkCatalogEntry.Knowledge)
        assertThrows(Exception::class.java) {
            ProtocolJson.decodeFromString(
                WorkCatalogEntry.serializer(),
                """
                {"id":"k","kind":"knowledge","name":"Docs","description":"","enabled":true,"roots":["/tmp"],"readOnly":false}
                """.trimIndent()
            )
        }
        val membership = ProtocolJson.decodeFromString(WorkMembership.serializer(), """{"revision":0,"binding":null}""")
        assertNull(membership.binding)
        val encoded = ProtocolJson.encodeToString(WorkMembership.serializer(), membership)
        assertTrue(encoded.contains("\"binding\":null"))
        val posted = ProtocolJson.decodeFromString(
            WorkEvent.serializer(),
            """
            {"type":"chat.posted","id":"event-1","workId":"work-1","seq":4,"createdAt":100,
             "actor":{"kind":"user","id":"local-user"},"messageId":"message-1",
             "body":"Please review task one","mentionedAgentIds":["agent-1"]}
            """.trimIndent()
        )
        assertTrue(posted is WorkEvent.ChatPosted)
        assertEquals(4, posted.seq)
    }

    @Test
    fun actionsAvailableCanOnlyBeFalse() {
        val snapshot = ProactiveSnapshot(
            defaultAgentId = null,
            agents = emptyList(),
            availableSourceIds = emptyList(),
            actionsAvailable = false
        )
        val json = ProtocolJson.encodeToString(ProactiveSnapshot.serializer(), snapshot)
        assertTrue(json.contains("\"actionsAvailable\":false"))
        val roundTrip = ProtocolJson.decodeFromString(ProactiveSnapshot.serializer(), json)
        assertFalse(roundTrip.actionsAvailable)
        val rejected = assertThrows(Exception::class.java) {
            ProtocolJson.decodeFromString(
                ProactiveSnapshot.serializer(),
                json.replace("\"actionsAvailable\":false", "\"actionsAvailable\":true")
            )
        }
        assertTrue(rejected.message.orEmpty().contains("false") || rejected.cause?.message.orEmpty().contains("false"))
        assertThrows(IllegalArgumentException::class.java) {
            ProactiveSnapshot(null, emptyList(), emptyList(), true)
        }
        assertThrows(Exception::class.java) {
            ProtocolJson.decodeFromString(
                ProactiveSnapshot.serializer(),
                """{"defaultAgentId":null,"agents":[],"availableSourceIds":[]}"""
            )
        }
        val duplicate = assertThrows(ProtocolParseException::class.java) {
            validateProactivePolicy(
                ProactivePolicy(revision = 1, sourceIds = listOf("calendar", "calendar"))
            )
        }
        assertTrue(duplicate.message!!.contains(DUPLICATE_CONTEXT_SOURCE))
        assertEquals(60_000L, PROACTIVE_INTERVAL_MIN_MS)
        assertEquals(3_600_000L, PROACTIVE_INTERVAL_MAX_MS)
        assertEquals(300_000L, PROACTIVE_INTERVAL_DEFAULT_MS)
    }

    @Test
    fun imageAdds8192TokensAndDoesNotCountItsBytes() {
        val message = ChatMessage(
            id = "m",
            role = MessageRole.USER,
            content = "hi",
            seq = 1,
            createdAt = 1
        )
        val payload = "A".repeat(10_000)
        val withImage = message.copy(images = listOf(ModelImage("image/png", payload)))
        val withTwo = message.copy(
            images = listOf(ModelImage("image/png", payload), ModelImage("image/jpeg", "BBBB"))
        )
        assertEquals(estimateModelTokens(listOf(message)) + 8192, estimateModelTokens(listOf(withImage)))
        assertEquals(estimateModelTokens(listOf(message)) + 16384, estimateModelTokens(listOf(withTwo)))
        val cjk = message.copy(content = message.content + "你")
        assertEquals(estimateModelTokens(listOf(message)) + 2, estimateModelTokens(listOf(cjk)))
    }

    @Test
    fun sendMessageKeepsTheModelFacingSentences() {
        val misplaced = assertThrows(ProtocolParseException::class.java) {
            parseSendMessage(jsonObject("type" to "text", "content" to "hi", "path" to "/tmp/a"))
        }
        assertEquals(
            "path: path is only valid with type:attachment, not type:text — it would be silently dropped. Nothing was sent. Re-send as separate SendMessage calls, one per type.",
            misplaced.message
        )
        val both = assertThrows(ProtocolParseException::class.java) {
            parseSendMessage(jsonObject("type" to "text", "path" to "/tmp/a"))
        }
        assertTrue(both.message!!.startsWith("path: path is only valid with type:attachment"))
        assertTrue(both.message!!.contains("content: content is required when type is text. Nothing was sent."))
        assertTrue(toolArgumentError("SendMessage", misplaced).startsWith("SendMessage: invalid arguments — "))
        val missing = assertThrows(ProtocolParseException::class.java) {
            parseSendMessage(jsonObject("type" to "text"))
        }
        assertEquals("content: content is required when type is text. Nothing was sent.", missing.message)
        val missingFile = assertThrows(ProtocolParseException::class.java) {
            parseSendMessage(jsonObject("type" to "attachment"))
        }
        assertEquals("path: path is required when type is attachment. Nothing was sent.", missingFile.message)
        val missingWidget = assertThrows(ProtocolParseException::class.java) {
            parseSendMessage(jsonObject("type" to "widget"))
        }
        assertEquals(
            "widget: widget is required when type is widget: an object with prompt and options. Nothing was sent.",
            missingWidget.message
        )
        val sent = parseSendMessage(jsonObject("type" to "text", "content" to "hi"))
        assertEquals(OutboundMessage.Text("hi"), sent)
        val legacy = parseOutboundMessage(
            jsonObject(
                "type" to "text",
                "text" to "hi",
                "images" to listOf("/tmp/a.png", jsonObject("path" to "/tmp/b.png", "alt" to "b"))
            )
        )
        assertEquals(
            OutboundMessage.Text(
                "hi",
                listOf(OutboundImage("/tmp/a.png"), OutboundImage("/tmp/b.png", "b"))
            ),
            legacy
        )
    }

    @Test
    fun errorCodesMatchTheMacNumbers() {
        assertEquals(1000, KernelErrorCode.INTERNAL)
        assertEquals(1002, KernelErrorCode.TURN_BUSY)
        assertEquals(1003, KernelErrorCode.CANCELLED)
        assertEquals(1004, KernelErrorCode.MODEL)
        assertEquals(1005, KernelErrorCode.TOOL)
        assertEquals(1006, KernelErrorCode.SANDBOX)
        assertEquals(1007, KernelErrorCode.INVALID)
        assertEquals(2001, HostErrorCode.AGENT_NOT_FOUND)
        assertEquals(2004, HostErrorCode.NO_API_KEY)
        assertEquals(2008, HostErrorCode.KERNEL_DOWN)
        assertEquals(2012, HostErrorCode.WORK_FORBIDDEN)
        assertEquals(3001, DesktopErrorCode.SECRET_STORE)
        assertEquals(3002, DesktopErrorCode.FOLDER_PICK)
        assertEquals(3003, DesktopErrorCode.WINDOW)
        val error = RpcError(KernelErrorCode.MODEL, "provider failed")
        assertEquals(1004, error.code)
        assertEquals("provider failed", error.message)
    }

    @Test
    fun transcriptProjectionKeepsDeliveredMessagesAndStripsRoomPrompts() {
        val user = parseTranscriptLine(jsonObject("type" to "user", "id" to "u", "seq" to 1, "createdAt" to 1, "text" to "x"))
        assertEquals(TranscriptEvent.User("u", 1, 1, "x"), user)
        val legacyUser = parseTranscriptLine(
            jsonObject("id" to "u1", "role" to "user", "content" to "hello", "seq" to 1, "createdAt" to 10)
        )
        assertEquals(TranscriptEvent.User("u1", 1, 10, "hello"), legacyUser)
        assertNull(
            eventFromChatMessage(ChatMessage("sys", MessageRole.SYSTEM, "hidden", seq = 0, createdAt = 0))
        )
        val view = projectAgent(
            listOf(
                TranscriptEvent.User("u1", 1, 1, "say hi"),
                TranscriptEvent.Assistant(
                    "a1",
                    2,
                    2,
                    listOf(
                        AssistantPart.Text("draft: maybe say hello"),
                        AssistantPart.ToolCall("c1", name = "SendMessage", arguments = jsonObject("type" to "text", "content" to "hi"))
                    )
                ),
                TranscriptEvent.Message(
                    "m1",
                    3,
                    3,
                    assistantId = "a1",
                    toolCallId = "c1",
                    payload = OutboundMessage.Text("hi")
                )
            )
        )
        assertTrue(view.blocks[0] is ViewBlock.User)
        assertTrue(view.blocks[1] is ViewBlock.Message)
        val room = projectAgent(
            listOf(
                TranscriptEvent.Wake(
                    id = "w",
                    seq = 1,
                    createdAt = 1,
                    source = WakeSource.Work("room", "Design", "bridge"),
                    text = "Trigger: internal instructions",
                    hops = 0
                )
            )
        )
        val notice = room.blocks.single() as ViewBlock.Notice
        assertTrue(notice.text.contains("Design"))
        assertFalse(notice.text.contains("Trigger:"))
        assertNull(tryParseTranscriptLine("{"))
    }

    @Test
    fun networkTargetsOnlyAllowHostPorts80And443() {
        assertTrue(isNetworkTarget("example.com:443"))
        assertTrue(isNetworkTarget("example.com:80"))
        assertFalse(isNetworkTarget("example.com:22"))
        assertFalse(isNetworkTarget("http://example.com:443"))
        assertFalse(isNetworkTarget("example.com"))
    }

    @Test
    fun rolledAvatarStaysInsideThePublishedEditionSet() {
        val roll = rollAgentAvatar(kotlin.random.Random(7))
        assertTrue(roll.color in AGENT_AVATAR_COLORS.map { it.id })
        assertTrue(roll.shape in AGENT_AVATAR_SHAPES)
        assertTrue(roll.material in AGENT_AVATAR_MATERIALS)
        assertEquals("aurora", resolveAgentAvatarMaterial("aurora"))
        assertEquals("plush", resolveAgentAvatarMaterial("unknown"))
    }

    /**
     * Shell is outside the PoC, but these patterns are the Mac `DENY_COMMANDS` list.
     * They have no call site until a shell exists; the text stays here so it is not lost.
     */
    @Test
    fun deniedCommandPatternsArePreserved() {
        val deny = listOf(
            Regex("""\brm\s+(?:-[a-zA-Z]*r[a-zA-Z]*f|-[a-zA-Z]*f[a-zA-Z]*r)\s+(?:/|~|\${'$'}HOME)(?:\s|$)"""),
            Regex("""\bmkfs\b"""),
            Regex("""\bdd\s+if="""),
            Regex(""":\(\)\s*\{\s*:\|\:&\s*\};:""")
        )
        assertTrue(deny.any { it.containsMatchIn("rm -rf /") })
        assertTrue(deny.any { it.containsMatchIn("rm -fr ~") })
        assertTrue(deny.any { it.containsMatchIn("rm -rf ${'$'}HOME") })
        assertTrue(deny.any { it.containsMatchIn("mkfs.ext4 /dev/sda") })
        assertTrue(deny.any { it.containsMatchIn("dd if=/dev/zero of=disk") })
        assertTrue(deny.any { it.containsMatchIn(":(){ :|:& };:") })
        assertTrue(deny.none { it.containsMatchIn("rm file.txt") })
        assertTrue(deny.none { it.containsMatchIn("echo hello") })
    }
}
