package com.nuum.feature.shell.model

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.nuum.contracts.AgentCreateParams
import com.nuum.contracts.AgentUpdateParams
import com.nuum.contracts.AgentView
import com.nuum.contracts.AssistantPart
import com.nuum.contracts.CommandGrant
import com.nuum.contracts.CommandPermission
import com.nuum.contracts.ExecutionPreferences
import com.nuum.contracts.HostEvent
import com.nuum.contracts.Language
import com.nuum.contracts.NetworkGrant
import com.nuum.contracts.NuumException
import com.nuum.contracts.OutboundMessage
import com.nuum.contracts.SettingsPatch
import com.nuum.contracts.SidebarOrganization
import com.nuum.contracts.ThemePreference
import com.nuum.contracts.TranscriptEvent
import com.nuum.contracts.TranscriptQuery
import com.nuum.contracts.WorkListItem
import com.nuum.contracts.WorkMemberAttachParams
import com.nuum.contracts.WorkMemberMoveParams
import com.nuum.contracts.WorkspaceSettings
import com.nuum.feature.shell.ShellPorts
import com.nuum.feature.shell.sidebar.COPY_FAILED
import com.nuum.feature.shell.sidebar.SIDEBAR_SAVE_FAILED
import com.nuum.feature.shell.sidebar.SidebarLayoutState
import com.nuum.feature.shell.sidebar.prepareSidebarSave
import com.nuum.feature.shell.sidebar.protocolSentence
import com.nuum.feature.shell.sidebar.toggleSidebarPin
import com.nuum.feature.shell.sidebar.withGroup
import com.nuum.protocol.ProtocolParseException
import com.nuum.protocol.normalizeAgentTags
import java.util.UUID
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch

internal const val IDENTITY_SAVE_FAILED = "Could not save. Please try again."
internal const val NAME_EMPTY = "Name cannot be empty."

internal class GroupDialogState(
    val sectionId: String?,
    val agentId: String?,
    val initialName: String
)

internal class ShellModel(
    private val ports: ShellPorts,
    private val scope: CoroutineScope
) {
    var settings by mutableStateOf(portsPlaceholderSettings())
    var settingsReady by mutableStateOf(false)
    var agents by mutableStateOf<List<AgentView>>(emptyList())
    var works by mutableStateOf<List<WorkListItem>>(emptyList())
    var previews by mutableStateOf<Map<String, String>>(emptyMap())
    var loaded by mutableStateOf(false)

    var selectedAgentId by mutableStateOf<String?>(null)
    var selectedWorkId by mutableStateOf<String?>(null)
    var showSettings by mutableStateOf(false)
    var createWork by mutableStateOf(false)
    var createOpen by mutableStateOf(false)
    var profileId by mutableStateOf<String?>(null)
    var identityOpen by mutableStateOf(false)
    var drawerOpen by mutableStateOf(true)
    var compact by mutableStateOf(true)

    var query by mutableStateOf("")
    var searchOpen by mutableStateOf(false)
    var busy by mutableStateOf(false)
    var notice by mutableStateOf<String?>(null)
    var newMenu by mutableStateOf(false)
    var menuAgentId by mutableStateOf<String?>(null)
    var menuSectionId by mutableStateOf<String?>(null)
    var menuGroups by mutableStateOf(false)
    var groupDialog by mutableStateOf<GroupDialogState?>(null)
    var dialogError by mutableStateOf<String?>(null)

    var layout by mutableStateOf(SidebarLayoutState())
    var resizing by mutableStateOf(false)
    var liveWidth by mutableStateOf<Int?>(null)
    private var layoutBeforeResize: SidebarLayoutState = layout

    var dragAgentId by mutableStateOf<String?>(null)
    var dragToken by mutableStateOf(0)

    var identityEdited by mutableStateOf<Set<String>>(emptySet())
    var workspaceRevoked by mutableStateOf<Set<String>>(emptySet())

    var creating by mutableStateOf(false)
    var createError by mutableStateOf<String?>(null)
    var executionSaving by mutableStateOf(false)
    var executionError by mutableStateOf<String?>(null)
    var identitySaving by mutableStateOf(false)
    var identityError by mutableStateOf<String?>(null)

    val organization: SidebarOrganization
        get() = settings.sidebar ?: SidebarOrganization()

    val language: Language
        get() = if (settingsReady) settings.language else Language.ZH_CN

    val theme: ThemePreference?
        get() = if (settingsReady) settings.theme else null

    val menuOpen: Boolean
        get() = menuAgentId != null || menuSectionId != null

    val canInterceptBack: Boolean
        get() = newMenu || menuOpen || groupDialog != null || identityOpen || createOpen ||
            profileId != null || showSettings || createWork || resizing || dragAgentId != null ||
            (compact && drawerOpen) || selectedAgentId != null || selectedWorkId != null

    suspend fun activate() = coroutineScope {
        launch { collect(ports.settings.events) { event ->
            if (event is HostEvent.SettingsUpdated) settings = event.settings
        } }
        launch { collect(ports.agents.events) { event ->
            if (event is HostEvent.AgentUpdated) replaceAgent(event.agent)
        } }
        launch { collect(ports.work.events) { refreshWorks() } }
        refresh()
    }

    fun back() {
        when {
            newMenu -> newMenu = false
            menuOpen -> closeMenu()
            groupDialog != null -> if (!busy) closeGroupDialog()
            identityOpen -> if (!identitySaving) closeIdentity()
            createOpen -> if (!creating) closeCreate()
            profileId != null -> closeProfile()
            showSettings || createWork -> dismissOverlay()
            resizing -> cancelResize()
            dragAgentId != null -> cancelDrag()
            compact && drawerOpen -> drawerOpen = false
            selectedAgentId != null || selectedWorkId != null -> {
                selectedAgentId = null
                selectedWorkId = null
                if (compact) drawerOpen = true
            }
        }
    }

    fun dismissOverlay() {
        showSettings = false
        createWork = false
    }

    fun openSettings() {
        showSettings = true
        createWork = false
        newMenu = false
        drawerOpen = false
    }

    fun openCreateWork() {
        createWork = true
        showSettings = false
        newMenu = false
        drawerOpen = false
    }

    fun openCreateNunu() {
        createOpen = true
        createError = null
        newMenu = false
        drawerOpen = false
    }

    fun openProfile(id: String) {
        profileId = id
        identityOpen = false
        identityError = null
        executionError = null
        closeMenu()
        drawerOpen = false
    }

    fun selectAgent(id: String) {
        selectedAgentId = id
        selectedWorkId = null
        showSettings = false
        createWork = false
        if (compact) drawerOpen = false
    }

    fun selectWork(id: String) {
        selectedWorkId = id
        selectedAgentId = null
        showSettings = false
        createWork = false
        if (compact) drawerOpen = false
    }

    fun openAgentMenu(id: String) {
        menuAgentId = id
        menuSectionId = null
        menuGroups = false
        newMenu = false
    }

    fun openSectionMenu(id: String) {
        menuSectionId = id
        menuAgentId = null
        menuGroups = false
        newMenu = false
    }

    fun closeMenu() {
        menuAgentId = null
        menuSectionId = null
        menuGroups = false
    }

    fun closeGroupDialog() {
        groupDialog = null
        dialogError = null
    }

    fun closeCreate() {
        createOpen = false
        createError = null
        creating = false
    }

    fun closeProfile() {
        profileId = null
        identityOpen = false
        identityError = null
    }

    fun closeIdentity() {
        identityOpen = false
        identityError = null
    }

    fun beginResize(current: Int) {
        layoutBeforeResize = layout
        resizing = true
        liveWidth = current
    }

    fun updateResize(width: Int) {
        if (resizing) liveWidth = width
    }

    fun endResize(windowDp: Int) {
        val live = liveWidth ?: return
        layout = com.nuum.feature.shell.sidebar.settleSidebarLayout(live, layoutBeforeResize.expandedWidth, windowDp)
        resizing = false
        liveWidth = null
    }

    fun cancelResize() {
        layout = layoutBeforeResize
        resizing = false
        liveWidth = null
    }

    fun cancelDrag() {
        dragToken += 1
        dragAgentId = null
    }

    fun pin(id: String) = commit(toggleSidebarPin(organization, id), fromDialog = false)

    fun saveOrganization(next: SidebarOrganization) = commit(next, fromDialog = false)

    fun openNewGroup(agentId: String?) {
        closeMenu()
        notice = null
        dialogError = null
        groupDialog = GroupDialogState(sectionId = null, agentId = agentId, initialName = "")
    }

    fun openRename(sectionId: String, name: String) {
        closeMenu()
        notice = null
        dialogError = null
        groupDialog = GroupDialogState(sectionId = sectionId, agentId = null, initialName = name)
    }

    fun saveGroup(name: String) {
        val dialog = groupDialog ?: return
        val trimmed = name.trim()
        if (trimmed.isEmpty() || busy) return
        val next = withGroup(
            state = organization,
            sectionId = dialog.sectionId,
            agentId = dialog.agentId,
            name = trimmed,
            newId = UUID.randomUUID().toString()
        )
        commit(next, fromDialog = true)
    }

    fun createAgent(name: String, color: String, shape: String, material: String) {
        val trimmed = name.trim()
        if (trimmed.isEmpty() || creating) return
        scope.launch {
            creating = true
            createError = null
            try {
                val created = ports.agents.create(
                    AgentCreateParams(
                        name = trimmed,
                        description = "",
                        avatarColor = color,
                        avatarShape = shape,
                        avatarMaterial = material
                    )
                )
                replaceAgent(created)
                if (agents.none { it.profile.id == created.profile.id }) {
                    agents = agents + created
                }
                selectAgent(created.profile.id)
                closeCreate()
            } catch (error: NuumException) {
                createError = error.message
            } catch (error: Exception) {
                createError = error.message ?: IDENTITY_SAVE_FAILED
            } finally {
                creating = false
            }
        }
    }

    fun saveIdentity(id: String, name: String, tagsRaw: String, description: String) {
        val trimmed = name.trim()
        if (trimmed.isEmpty()) {
            identityError = NAME_EMPTY
            return
        }
        scope.launch {
            identitySaving = true
            identityError = null
            try {
                val tags = normalizeAgentTags(splitTags(tagsRaw))
                val updated = ports.agents.update(
                    AgentUpdateParams(
                        id = id,
                        name = trimmed,
                        description = description.trim(),
                        tags = tags
                    )
                )
                replaceAgent(updated)
                identityEdited = identityEdited + id
                closeIdentity()
            } catch (error: ProtocolParseException) {
                identityError = protocolSentence(error)
            } catch (error: NuumException) {
                identityError = error.message?.ifBlank { IDENTITY_SAVE_FAILED } ?: IDENTITY_SAVE_FAILED
            } catch (_: Exception) {
                identityError = IDENTITY_SAVE_FAILED
            } finally {
                identitySaving = false
            }
        }
    }

    fun setCommands(agent: AgentView, commands: CommandPermission) {
        val current = agent.settings.execution
        val next = ExecutionPreferences(
            workspaceId = current?.workspaceId ?: agent.profile.id,
            commands = commands,
            commandGrants = current?.commandGrants ?: emptyList(),
            networkGrants = current?.networkGrants ?: emptyList()
        )
        saveExecution(agent.profile.id, next)
    }

    fun revokeCommand(agent: AgentView, grant: CommandGrant) {
        val current = agent.settings.execution ?: return
        saveExecution(agent.profile.id, current.copy(commandGrants = current.commandGrants.filterNot { it == grant }))
    }

    fun revokeNetwork(agent: AgentView, grant: NetworkGrant) {
        val current = agent.settings.execution ?: return
        saveExecution(agent.profile.id, current.copy(networkGrants = current.networkGrants.filterNot { it == grant }))
    }

    fun openFolder(agent: AgentView) {
        scope.launch {
            executionSaving = true
            executionError = null
            try {
                val revoked = agent.profile.id in workspaceRevoked
                val root = agent.settings.workspace?.projectRoot
                if (revoked || root.isNullOrBlank()) {
                    val picked = ports.desktop.pickDirectory()
                    if (picked != null) {
                        val updated = ports.agents.update(
                            AgentUpdateParams(
                                id = agent.profile.id,
                                workspace = WorkspaceSettings(
                                    projectRoot = picked,
                                    toolPermission = agent.settings.workspace?.toolPermission
                                )
                            )
                        )
                        workspaceRevoked = workspaceRevoked - agent.profile.id
                        replaceAgent(updated)
                    }
                } else {
                    try {
                        ports.desktop.openAttachment(root)
                    } catch (error: NuumException) {
                        workspaceRevoked = workspaceRevoked + agent.profile.id
                        executionError = error.message
                    }
                }
            } catch (error: NuumException) {
                executionError = error.message
            } catch (error: Exception) {
                executionError = error.message ?: IDENTITY_SAVE_FAILED
            } finally {
                executionSaving = false
            }
        }
    }

    fun moveAgentToWork(agentId: String, workId: String) {
        val agent = agents.find { it.profile.id == agentId } ?: return
        scope.launch {
            try {
                val membership = agent.settings.workMembership
                val binding = membership?.binding
                if (binding != null && binding.workId != workId) {
                    ports.work.moveMember(
                        WorkMemberMoveParams(
                            fromWorkId = binding.workId,
                            toWorkId = workId,
                            agentId = agentId,
                            expectedRevision = membership.revision
                        )
                    )
                } else if (binding?.workId != workId) {
                    ports.work.attachMember(
                        WorkMemberAttachParams(
                            workId = workId,
                            agentId = agentId,
                            expectedRevision = membership?.revision ?: 0
                        )
                    )
                }
                refreshAgents()
            } catch (error: NuumException) {
                notice = error.message?.ifBlank { SIDEBAR_SAVE_FAILED } ?: SIDEBAR_SAVE_FAILED
            } catch (_: Exception) {
                notice = SIDEBAR_SAVE_FAILED
            }
        }
    }

    fun noteCopy(ok: Boolean) {
        notice = if (ok) null else COPY_FAILED
    }

    private fun saveExecution(id: String, execution: ExecutionPreferences) {
        scope.launch {
            executionSaving = true
            executionError = null
            try {
                val updated = ports.agents.update(AgentUpdateParams(id = id, execution = execution))
                replaceAgent(updated)
            } catch (error: NuumException) {
                executionError = error.message
            } catch (error: Exception) {
                executionError = error.message ?: IDENTITY_SAVE_FAILED
            } finally {
                executionSaving = false
            }
        }
    }

    private fun commit(next: SidebarOrganization, fromDialog: Boolean) {
        if (busy) return
        val prepared = try {
            prepareSidebarSave(next)
        } catch (error: ProtocolParseException) {
            presentSaveError(protocolSentence(error), fromDialog)
            return
        }
        scope.launch {
            busy = true
            if (fromDialog) dialogError = null else notice = null
            try {
                settings = ports.settings.set(SettingsPatch(sidebar = prepared))
                settingsReady = true
                if (fromDialog) closeGroupDialog() else closeMenu()
            } catch (error: ProtocolParseException) {
                presentSaveError(protocolSentence(error), fromDialog)
            } catch (error: NuumException) {
                presentSaveError(error.message?.ifBlank { SIDEBAR_SAVE_FAILED } ?: SIDEBAR_SAVE_FAILED, fromDialog)
            } catch (_: Exception) {
                presentSaveError(SIDEBAR_SAVE_FAILED, fromDialog)
            } finally {
                busy = false
            }
        }
    }

    private fun presentSaveError(message: String, fromDialog: Boolean) {
        if (fromDialog) dialogError = message else notice = message
    }

    private suspend fun refresh() {
        try {
            settings = ports.settings.get()
            settingsReady = true
            refreshAgents()
            refreshWorks()
        } finally {
            loaded = true
        }
    }

    private suspend fun refreshAgents() {
        agents = ports.agents.list()
        previews = loadPreviews(agents)
    }

    private suspend fun refreshWorks() {
        works = ports.work.list()
    }

    private suspend fun loadPreviews(listed: List<AgentView>): Map<String, String> {
        val out = linkedMapOf<String, String>()
        for (agent in listed) {
            val text = try {
                val page = ports.agents.transcript(TranscriptQuery(id = agent.profile.id, limit = 40))
                page.entries.mapNotNull { previewOf(it) }.lastOrNull()
            } catch (_: Exception) {
                null
            }
            if (!text.isNullOrBlank()) out[agent.profile.id] = text
        }
        return out
    }

    private fun replaceAgent(view: AgentView) {
        agents = if (agents.any { it.profile.id == view.profile.id }) {
            agents.map { if (it.profile.id == view.profile.id) view else it }
        } else {
            agents + view
        }
    }

    private suspend fun collect(events: kotlinx.coroutines.flow.Flow<HostEvent>, onEvent: suspend (HostEvent) -> Unit) {
        events.collect { event -> onEvent(event) }
    }
}

private fun portsPlaceholderSettings() = com.nuum.contracts.PublicSettings(
    defaultToolPermission = com.nuum.contracts.ToolPermission.ASK,
    defaultModel = com.nuum.contracts.ModelRef(
        com.nuum.contracts.ProviderId.DEEPSEEK,
        com.nuum.contracts.DEFAULT_MODEL_ID.getValue(com.nuum.contracts.ProviderId.DEEPSEEK)
    ),
    theme = ThemePreference.DARK,
    hasOpenaiKey = false,
    hasAnthropicKey = false,
    hasDeepseekKey = false,
    language = Language.ZH_CN,
    sidebar = null
)

internal fun splitTags(raw: String): List<String> =
    raw.split(',', '，', '、', '\n').map { it.trim() }.filter { it.isNotEmpty() }

internal fun previewOf(event: TranscriptEvent): String? = when (event) {
    is TranscriptEvent.User -> event.text.takeIf { it.isNotBlank() }
    is TranscriptEvent.Assistant -> event.parts.filterIsInstance<AssistantPart.Text>().lastOrNull()?.text?.takeIf { it.isNotBlank() }
    is TranscriptEvent.Message -> when (val payload = event.payload) {
        is OutboundMessage.Text -> payload.content.takeIf { it.isNotBlank() }
        is OutboundMessage.Attachment -> payload.caption?.takeIf { it.isNotBlank() }
        else -> null
    }
    is TranscriptEvent.Wake -> event.text.takeIf { it.isNotBlank() }
    else -> null
}
