package com.nuum.feature.conversation

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.isShiftPressed
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import androidx.compose.runtime.collectAsState
import com.nuum.contracts.AgentStatus
import com.nuum.contracts.AgentView
import com.nuum.contracts.ViewBlock
import kotlinx.coroutines.flow.distinctUntilChanged

@Composable
fun ConversationScreen(
    agentId: String,
    ports: ConversationPorts,
    modifier: Modifier = Modifier,
    onOpenAgents: (() -> Unit)? = null,
    onOpenProfile: (() -> Unit)? = null,
    dark: Boolean = true
) {
    val model = remember(agentId, ports) { ConversationModel(agentId, ports) }
    LaunchedEffect(model) { model.run() }
    val state by model.state.collectAsState()
    ConversationTheme(dark = dark) {
        ConversationBody(
            state = state,
            model = model,
            onOpenAgents = onOpenAgents,
            onOpenProfile = onOpenProfile,
            modifier = modifier
        )
    }
}

@Composable
private fun ConversationBody(
    state: ConversationUiState,
    model: ConversationModel,
    onOpenAgents: (() -> Unit)?,
    onOpenProfile: (() -> Unit)?,
    modifier: Modifier
) {
    val blocks = state.visibleBlocks()
    val approval = oneToOneApproval(state.pending)
    val agent = state.agent
    val activity = activityState(
        status = if (state.streaming && agent?.runtime?.status != AgentStatus.ERROR) {
            AgentStatus.RUNNING
        } else {
            agent?.runtime?.status ?: AgentStatus.IDLE
        },
        awaitingApproval = approval != null,
        executingTool = hasExecutingTool(blocks)
    )
    val showActivity = state.showStop
    BoxWithConstraints(
        modifier
            .fillMaxSize()
            .background(Sand.bgEditor)
            .statusBarsPadding()
    ) {
        val phone = maxWidth < 840.dp
        Column(Modifier.fillMaxSize()) {
            TopBar(
                phone = phone,
                agent = agent,
                activity = activity,
                showActivity = showActivity,
                onOpenAgents = onOpenAgents,
                onOpenProfile = onOpenProfile
            )
            Box(Modifier.weight(1f).fillMaxWidth()) {
                when {
                    state.phase == Phase.Loading -> Box(Modifier.fillMaxSize())
                    blocks.isEmpty() -> EmptyWelcome()
                    agent != null -> TranscriptRegion(state, blocks, agent, model)
                }
                Box(
                    Modifier
                        .align(Alignment.TopCenter)
                        .fillMaxWidth()
                        .height(46.dp)
                        .background(Brush.verticalGradient(listOf(Sand.bgEditor, Sand.bgEditor.copy(alpha = 0f))))
                )
            }
            ComposerDock(state, approval, activity, showActivity, model)
        }
        val peerId = state.openPeerId
        if (peerId != null && agent != null) {
            BackHandler { model.closePeer() }
            PeerSheet(
                phone = phone,
                agent = agent,
                peerId = peerId,
                peers = state.peers,
                blocks = blocks.filterIsInstance<ViewBlock.Peer>().filter { it.agentId == peerId },
                timestamps = transcriptTimestamps(state.events),
                onClose = model::closePeer
            )
        }
    }
}

@Composable
private fun TopBar(
    phone: Boolean,
    agent: AgentView?,
    activity: String,
    showActivity: Boolean,
    onOpenAgents: (() -> Unit)?,
    onOpenProfile: (() -> Unit)?
) {
    Row(
        Modifier
            .fillMaxWidth()
            .height(56.dp)
            .padding(horizontal = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        if (phone) {
            val agents = copy(R.string.agents)
            Box(
                Modifier
                    .size(48.dp)
                    .clickable { onOpenAgents?.invoke() }
                    .semantics { role = Role.Button; contentDescription = agents },
                contentAlignment = Alignment.Center
            ) {
                SandIcon("chevron-right", Modifier.size(16.dp), Sand.textPrimary)
            }
        }
        if (agent != null) {
            val profile = copy(R.string.open_profile, "name" to agent.profile.name)
            Row(
                Modifier
                    .weight(1f)
                    .heightIn(min = 48.dp)
                    .clickable(enabled = onOpenProfile != null) { onOpenProfile?.invoke() }
                    .semantics { role = Role.Button; contentDescription = profile }
                    .padding(horizontal = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                NunuAvatar(
                    agentId = agent.profile.id,
                    colorId = agent.profile.avatarColor,
                    shapeId = agent.profile.avatarShape,
                    materialId = agent.profile.avatarMaterial,
                    size = 28.dp,
                    activity = activity
                )
                Text(agent.profile.name, color = Sand.textPrimary, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                if (showActivity) {
                    Text(activityLabel(activity), color = Sand.textTertiary, fontSize = 12.sp)
                }
            }
        } else {
            Box(Modifier.weight(1f))
        }
    }
}

@Composable
private fun EmptyWelcome() {
    Column(
        Modifier.fillMaxSize(),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(
            "Nuum",
            color = Sand.textPrimary,
            fontSize = 28.sp,
            fontWeight = FontWeight.SemiBold,
            letterSpacing = (-0.04).em
        )
        Text(
            copy(R.string.ask_anything),
            color = Sand.textTertiary,
            fontSize = 13.sp,
            modifier = Modifier.padding(top = 10.dp)
        )
    }
}

@Composable
private fun TranscriptRegion(
    state: ConversationUiState,
    blocks: List<ViewBlock>,
    agent: AgentView,
    model: ConversationModel
) {
    val listState = rememberLazyListState()
    var stick by remember { mutableStateOf(true) }
    LaunchedEffect(listState) {
        snapshotFlow {
            val info = listState.layoutInfo
            val last = info.visibleItemsInfo.lastOrNull()?.index
            last == null || info.totalItemsCount == 0 || last >= info.totalItemsCount - 1
        }.distinctUntilChanged().collect { stick = it }
    }
    LaunchedEffect(blocks.size, blocks.lastOrNull()?.blockId()) {
        if (stick && blocks.isNotEmpty()) listState.scrollToItem(blocks.lastIndex)
    }
    TranscriptList(
        blocks = blocks,
        timestamps = transcriptTimestamps(state.events),
        listState = listState,
        peers = state.peers,
        chat = chatColor(agent.profile.id, agent.profile.avatarColor),
        widgetAnswers = widgetAnswers(blocks),
        widgetErrors = state.widgetErrors,
        widgetBusy = state.widgetBusy,
        onAnswer = model::answer,
        onOpenAttachment = model::openAttachment,
        onOpenPeer = model::openPeer,
        modifier = Modifier.fillMaxSize()
    )
}

@Composable
private fun ComposerDock(
    state: ConversationUiState,
    approval: PendingTool?,
    activity: String,
    showActivity: Boolean,
    model: ConversationModel
) {
    val agent = state.agent
    var menuOpen by remember(agent?.profile?.id) { mutableStateOf(false) }
    var field by remember { mutableStateOf(TextFieldValue()) }
    LaunchedEffect(state.draft) {
        if (field.text != state.draft) field = TextFieldValue(state.draft)
    }
    val placeholder = if (agent == null) {
        copy(R.string.ask_anything)
    } else {
        copy(R.string.message_name, "name" to agent.profile.name)
    }
    val canAttach = agent != null && !state.sending && !state.readingAttachments && !state.showStop
    val canSend = !state.showStop && !state.sending && !state.readingAttachments && !state.attachmentLimitBlocked &&
        (state.draft.isNotBlank() || state.attachments.isNotEmpty())
    Column(
        Modifier
            .fillMaxWidth()
            .background(Sand.bgEditor)
            .navigationBarsPadding()
            .padding(horizontal = 12.dp)
            .padding(bottom = 12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        if (showActivity && agent != null) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                NunuAvatar(
                    agentId = agent.profile.id,
                    colorId = agent.profile.avatarColor,
                    shapeId = agent.profile.avatarShape,
                    materialId = agent.profile.avatarMaterial,
                    size = 40.dp,
                    activity = activity
                )
                Text(activityLabel(activity), color = Sand.textTertiary, fontSize = 13.sp)
            }
        }
        if (approval != null) {
            ApprovalBar(
                pending = approval,
                busy = state.deciding,
                error = state.approvalError,
                onDecide = model::decide
            )
        }
        state.notice?.let { banner ->
            val text = when (banner) {
                is Banner.Localized -> copy(banner.key)
                is Banner.Raw -> banner.text.ifBlank { copy(CopyKey.HostError) }
            }
            NoticeText(text, banner.alert)
        }
        if (state.readingAttachments) NoticeText(copy(CopyKey.Reading), alert = false)
        if (!state.readingAttachments && state.attachmentError != null) {
            NoticeText(copy(state.attachmentError), alert = true)
        }
        val modelRef = agent?.settings?.model
        if (modelRef != null && state.attachments.any { isImageMime(it.mimeType) } && !supportsImageInput(modelRef)) {
            NoticeText(copy(CopyKey.NoImageSupport), alert = false)
        }
        if (state.attachments.isNotEmpty()) {
            AttachmentChips(
                files = state.attachments,
                enabled = !state.sending && !state.readingAttachments && !state.showStop,
                onRemove = model::removeAttachment
            )
        }
        Column(
            Modifier
                .fillMaxWidth()
                .border(1.dp, Sand.borderDefault, RoundedCornerShape(18.dp))
                .background(Sand.bgInput, RoundedCornerShape(18.dp))
                .padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            BasicTextField(
                value = field,
                onValueChange = { updated ->
                    field = updated
                    model.onDraft(updated.text)
                },
                enabled = !state.sending,
                textStyle = TextStyle(color = Sand.textPrimary, fontSize = 14.sp, lineHeight = 22.sp),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Send),
                keyboardActions = KeyboardActions(onSend = { if (!state.showStop) model.send() }),
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 24.dp, max = 120.dp)
                    .semantics { contentDescription = placeholder }
                    .onPreviewKeyEvent { event ->
                        if (event.type == KeyEventType.KeyDown && event.key == Key.Enter && !event.isShiftPressed) {
                            if (field.composition != null) return@onPreviewKeyEvent false
                            if (!state.showStop) model.send()
                            true
                        } else {
                            false
                        }
                    },
                decorationBox = { inner ->
                    Box {
                        if (field.text.isEmpty()) {
                            Text(placeholder, color = Sand.textTertiary, fontSize = 14.sp)
                        }
                        inner()
                    }
                }
            )
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                Box {
                    val actions = copy(R.string.composer_actions)
                    Box(
                        Modifier
                            .size(48.dp)
                            .clickable(enabled = canAttach) { menuOpen = !menuOpen }
                            .semantics { role = Role.Button; contentDescription = actions },
                        contentAlignment = Alignment.Center
                    ) {
                        SandIcon("plus", Modifier.size(20.dp), if (canAttach) Sand.textPrimary else Sand.textTertiary)
                    }
                    if (menuOpen) {
                        Column(
                            Modifier
                                .padding(bottom = 48.dp)
                                .align(Alignment.BottomStart)
                                .background(Sand.bgElevated, RoundedCornerShape(10.dp))
                                .border(1.dp, Sand.borderDefault, RoundedCornerShape(10.dp))
                        ) {
                            val add = copy(R.string.add_attachment)
                            Row(
                                Modifier
                                    .clickable {
                                        menuOpen = false
                                        model.pickAttachments()
                                    }
                                    .padding(horizontal = 12.dp, vertical = 12.dp)
                                    .semantics { role = Role.Button },
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                SandIcon("attach", Modifier.size(16.dp), Sand.textPrimary)
                                Text(add, color = Sand.textPrimary, fontSize = 13.sp)
                            }
                        }
                    }
                }
                if (state.showStop) {
                    val stop = copy(R.string.stop)
                    Box(
                        Modifier
                            .size(48.dp)
                            .clip(RoundedCornerShape(999.dp))
                            .background(Sand.fillPrimary)
                            .clickable { model.cancel() }
                            .semantics { role = Role.Button; contentDescription = stop },
                        contentAlignment = Alignment.Center
                    ) {
                        SandIcon("stop", Modifier.size(16.dp), Sand.textOnPrimary)
                    }
                } else {
                    val send = copy(R.string.send_message)
                    Box(
                        Modifier
                            .size(48.dp)
                            .clip(RoundedCornerShape(999.dp))
                            .background(if (canSend) Sand.fillPrimary else Sand.borderDefault)
                            .clickable(enabled = canSend) { model.send() }
                            .semantics { role = Role.Button; contentDescription = send },
                        contentAlignment = Alignment.Center
                    ) {
                        SandIcon("arrow-up", Modifier.size(16.dp), if (canSend) Sand.textOnPrimary else Sand.textTertiary)
                    }
                }
            }
        }
    }
}

@Composable
private fun NoticeText(text: String, alert: Boolean) {
    Text(
        text,
        color = if (alert) Sand.textDanger else Sand.textTertiary,
        fontSize = 11.sp,
        modifier = Modifier.semantics {
            liveRegion = if (alert) LiveRegionMode.Assertive else LiveRegionMode.Polite
            contentDescription = text
        }
    )
}

@Composable
private fun PeerSheet(
    phone: Boolean,
    agent: AgentView,
    peerId: String,
    peers: List<AgentView>,
    blocks: List<ViewBlock.Peer>,
    timestamps: Map<String, Long>,
    onClose: () -> Unit
) {
    val peer = peers.firstOrNull { it.profile.id == peerId }
    val peerName = peer?.profile?.name ?: blocks.firstOrNull()?.agentName ?: copy(R.string.agent_fallback)
    val title = copy(R.string.conversation_between, "first" to agent.profile.name, "second" to peerName)
    val chat = chatColor(agent.profile.id, agent.profile.avatarColor)
    Box(
        Modifier
            .fillMaxSize()
            .background(Sand.scrim)
            .clickable { onClose() }
            .semantics { contentDescription = title }
    ) {
        Column(
            Modifier
                .align(if (phone) Alignment.BottomCenter else Alignment.Center)
                .then(if (phone) Modifier.fillMaxWidth().fillMaxSize(0.88f) else Modifier.widthIn(max = 640.dp).fillMaxWidth(0.9f))
                .clip(RoundedCornerShape(topStart = 18.dp, topEnd = 18.dp, bottomStart = if (phone) 0.dp else 18.dp, bottomEnd = if (phone) 0.dp else 18.dp))
                .background(Sand.bgEditor)
                .clickable { }
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                NunuAvatar(agent.profile.id, agent.profile.avatarColor, agent.profile.avatarShape, agent.profile.avatarMaterial, 30.dp, "idle")
                Text(agent.profile.name, color = Sand.textPrimary, fontWeight = FontWeight.SemiBold)
                NunuAvatar(peerId, peer?.profile?.avatarColor, peer?.profile?.avatarShape, peer?.profile?.avatarMaterial, 30.dp, "idle")
                Text(peerName, color = Sand.textPrimary, fontWeight = FontWeight.SemiBold)
            }
            Text(title, color = Sand.textSecondary, fontSize = 12.sp)
            Column(Modifier.weight(1f, fill = false), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                blocks.forEach { block ->
                    val outbound = block.direction == "outbound"
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = if (outbound) Arrangement.End else Arrangement.Start) {
                        Text(
                            block.text,
                            color = if (outbound) Sand.textOnColor else Sand.textPrimary,
                            modifier = Modifier
                                .widthIn(max = 420.dp)
                                .background(if (outbound) chat else Sand.fillBubbleAgent, RoundedCornerShape(18.dp))
                                .padding(horizontal = 12.dp, vertical = 8.dp)
                        )
                    }
                }
            }
            val close = copy(R.string.close_agent_conversation)
            Text(
                close,
                color = Sand.textPrimary,
                modifier = Modifier
                    .clickable { onClose() }
                    .semantics { role = Role.Button; contentDescription = close }
            )
        }
    }
}
