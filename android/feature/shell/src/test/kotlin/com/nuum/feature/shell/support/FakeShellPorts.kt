package com.nuum.feature.shell.support

import com.nuum.contracts.AgentCreateParams
import com.nuum.contracts.AgentPort
import com.nuum.contracts.AgentSnapshot
import com.nuum.contracts.AgentUpdateParams
import com.nuum.contracts.AgentView
import com.nuum.contracts.DesktopPort
import com.nuum.contracts.HostEvent
import com.nuum.contracts.Language
import com.nuum.contracts.ModelRef
import com.nuum.contracts.PickedFile
import com.nuum.contracts.ProviderId
import com.nuum.contracts.PublicSettings
import com.nuum.contracts.SettingsPatch
import com.nuum.contracts.SettingsPort
import com.nuum.contracts.SidebarOrganization
import com.nuum.contracts.ThemePreference
import com.nuum.contracts.ToolPermission
import com.nuum.contracts.TranscriptPage
import com.nuum.contracts.TranscriptQuery
import com.nuum.contracts.WorkListItem
import com.nuum.contracts.WorkPort
import com.nuum.feature.shell.ShellPorts
import com.nuum.feature.shell.agent
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow

/** In-module fakes. Contracts stay free of test doubles. */
internal class FakeShellPorts(
    initialAgents: List<AgentView> = emptyList(),
    initialWorks: List<WorkListItem> = emptyList(),
    sidebar: SidebarOrganization? = null,
    language: Language = Language.EN
) {
    val created = mutableListOf<AgentCreateParams>()
    var sidebarSets: Int = 0
    var settings: PublicSettings = PublicSettings(
        defaultToolPermission = ToolPermission.ASK,
        defaultModel = ModelRef(ProviderId.DEEPSEEK, "deepseek-chat"),
        theme = ThemePreference.DARK,
        hasOpenaiKey = false,
        hasAnthropicKey = false,
        hasDeepseekKey = false,
        language = language,
        sidebar = sidebar
    )
    private val agents = initialAgents.toMutableList()
    private val works = initialWorks.toMutableList()
    private val events = MutableSharedFlow<HostEvent>(extraBufferCapacity = 4)

    val ports = ShellPorts(
        agents = object : AgentPort {
            override val events: Flow<HostEvent> = this@FakeShellPorts.events
            override suspend fun list(): List<AgentView> = agents.toList()
            override suspend fun get(id: String): AgentSnapshot {
                val view = agents.first { it.profile.id == id }
                return AgentSnapshot(view, emptyList(), emptyList(), null)
            }
            override suspend fun create(params: AgentCreateParams): AgentView {
                created += params
                val view = agent("created-${created.size}", params.name ?: "Nunu").let { base ->
                    base.copy(
                        profile = base.profile.copy(
                            description = params.description ?: "",
                            avatarColor = params.avatarColor,
                            avatarShape = params.avatarShape,
                            avatarMaterial = params.avatarMaterial
                        )
                    )
                }
                agents += view
                return view
            }
            override suspend fun update(params: AgentUpdateParams): AgentView {
                val current = agents.first { it.profile.id == params.id }
                val view = current.copy(
                    profile = current.profile.copy(
                        name = params.name ?: current.profile.name,
                        description = params.description ?: current.profile.description,
                        tags = params.tags ?: current.profile.tags
                    ),
                    settings = current.settings.copy(
                        execution = params.execution ?: current.settings.execution,
                        workspace = params.workspace ?: current.settings.workspace
                    )
                )
                val index = agents.indexOfFirst { it.profile.id == params.id }
                agents[index] = view
                return view
            }
            override suspend fun delete(id: String) = unsupported()
            override suspend fun transcript(query: TranscriptQuery): TranscriptPage =
                TranscriptPage(query.id, emptyList(), null)
            override suspend fun send(params: com.nuum.contracts.AgentSendParams) = unsupported()
            override suspend fun answerWidget(params: com.nuum.contracts.AgentAnswerWidgetParams) = unsupported()
            override suspend fun cancel(id: String) = unsupported()
            override suspend fun approve(id: String, toolCallId: String, resolution: com.nuum.contracts.ToolResolution) = unsupported()
            override suspend fun deny(id: String, toolCallId: String, resolution: com.nuum.contracts.ToolResolution) = unsupported()
        },
        settings = object : SettingsPort {
            override val events: Flow<HostEvent> = this@FakeShellPorts.events
            override suspend fun get(): PublicSettings = settings
            override suspend fun set(patch: SettingsPatch): PublicSettings {
                if (patch.sidebar != null) {
                    sidebarSets += 1
                    settings = settings.copy(sidebar = patch.sidebar)
                }
                patch.theme?.let { settings = settings.copy(theme = it) }
                patch.language?.let { settings = settings.copy(language = it) }
                return settings
            }
        },
        desktop = object : DesktopPort {
            override suspend fun pickDirectory(): String? = null
            override suspend fun pickFiles(): List<PickedFile> = emptyList()
            override suspend fun openAttachment(path: String) = Unit
            override suspend fun share(path: String) = Unit
        },
        work = object : WorkPort {
            override val events: Flow<HostEvent> = this@FakeShellPorts.events
            override suspend fun list(): List<WorkListItem> = works.toList()
            override suspend fun create(params: com.nuum.contracts.WorkCreateParams) = unsupported()
            override suspend fun get(id: String) = unsupported()
            override suspend fun update(params: com.nuum.contracts.WorkUpdateParams) = unsupported()
            override suspend fun postMessage(params: com.nuum.contracts.WorkPostMessageParams) = unsupported()
            override suspend fun attachMember(params: com.nuum.contracts.WorkMemberAttachParams) = unsupported()
            override suspend fun detachMember(params: com.nuum.contracts.WorkMemberDetachParams) = unsupported()
            override suspend fun moveMember(params: com.nuum.contracts.WorkMemberMoveParams) = unsupported()
            override suspend fun continueDiscussion(params: com.nuum.contracts.WorkContinueParams) = unsupported()
            override suspend fun stopDiscussion(workId: String) = unsupported()
            override suspend fun taskTranscript(params: com.nuum.contracts.WorkTaskTranscriptParams) = unsupported()
            override suspend fun transitionTask(params: com.nuum.contracts.WorkTaskTransitionParams) = unsupported()
            override suspend fun dispatch(params: com.nuum.contracts.WorkDispatchParams) = unsupported()
            override suspend fun addCatalog(params: com.nuum.contracts.WorkCatalogAddParams) = unsupported()
            override suspend fun removeCatalog(params: com.nuum.contracts.WorkCatalogRemoveParams) = unsupported()
        }
    )
}

private fun unsupported(): Nothing = throw UnsupportedOperationException("shell fixture")
