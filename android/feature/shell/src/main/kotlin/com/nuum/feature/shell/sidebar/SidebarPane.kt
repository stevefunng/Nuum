package com.nuum.feature.shell.sidebar

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.awaitTouchSlopOrCancellation
import androidx.compose.foundation.gestures.drag
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.onLongClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.nuum.contracts.AgentStatus
import com.nuum.contracts.AgentView
import com.nuum.contracts.SidebarOrganization
import com.nuum.contracts.WorkListItem
import com.nuum.feature.shell.chrome.ActionMenu
import com.nuum.feature.shell.chrome.AlertLine
import com.nuum.feature.shell.chrome.Glyph
import com.nuum.feature.shell.chrome.IconHit
import com.nuum.feature.shell.chrome.MenuEntry
import com.nuum.feature.shell.chrome.PillButton
import com.nuum.feature.shell.chrome.SandText
import com.nuum.feature.shell.chrome.nuum
import com.nuum.feature.shell.avatar.NunuAvatar
import com.nuum.feature.shell.model.ShellModel
import com.nuum.feature.shell.theme.LocalCopy
import com.nuum.feature.shell.theme.LocalSand
import kotlinx.coroutines.withTimeoutOrNull

@Composable
internal fun SidebarPane(
    model: ShellModel,
    modifier: Modifier = Modifier,
    showResize: Boolean = false,
    windowDp: Int = 840
) {
    val copy = LocalCopy.current
    val sand = LocalSand.current
    val width = displaySidebarWidth(model.layout, model.liveWidth, model.resizing)
    val collapsed = showResize && width <= SIDEBAR_COLLAPSED
    val barModifier = if (showResize) {
        Modifier.width(width.dp).fillMaxHeight()
    } else {
        Modifier.fillMaxWidth().fillMaxHeight()
    }
    val query = model.query
    val visible = visibleAgents(model.agents, query)
    val works = visibleWorks(model.works, query)
    val projection = projectSidebarAgents(visible, model.organization)
    val merged = mergedRows(projection.unassigned, works)
    val searching = query.isNotBlank()
    val dropBounds = remember { mutableMapOf<String, Rect>() }
    val hasRows = projection.pinned.isNotEmpty() ||
        projection.sections.any { it.agents.isNotEmpty() } ||
        merged.isNotEmpty()
    Box(modifier.fillMaxHeight()) {
    Column(
        barModifier
            .background(sand.bgChrome)
            .semantics { contentDescription = copy.t("Agents") }
    ) {
        if (!collapsed) {
            Row(Modifier.fillMaxWidth().padding(end = 4.dp), horizontalArrangement = Arrangement.End) {
                IconHit(
                    label = copy.t("Search"),
                    glyph = Glyph.Search,
                    expanded = model.searchOpen,
                    onClick = { model.searchOpen = !model.searchOpen }
                )
                IconHit(
                    label = copy.t("New"),
                    title = copy.t("New agent"),
                    glyph = Glyph.Plus,
                    expanded = model.newMenu,
                    onClick = { model.newMenu = !model.newMenu }
                )
            }
        }
        if (!collapsed && (model.searchOpen || query.isNotEmpty())) {
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                androidx.compose.foundation.layout.Box(Modifier.padding(end = 8.dp)) {
                    com.nuum.feature.shell.chrome.GlyphIcon(Glyph.Search, 16.dp, sand.textTertiary)
                }
                BasicTextField(
                    value = query,
                    onValueChange = { model.query = it },
                    singleLine = true,
                    textStyle = TextStyle(color = sand.textPrimary, fontSize = 13.nuum()),
                    modifier = Modifier
                        .weight(1f)
                        .border(width = 0.dp, color = sand.borderSubtle)
                        .padding(bottom = 4.dp)
                        .semantics { contentDescription = copy.t("Search") },
                    decorationBox = { inner ->
                        Box {
                            if (query.isEmpty()) SandText(copy.t("Search"), sand.textTertiary, 13)
                            inner()
                        }
                    }
                )
            }
        }
        if (model.dragAgentId != null && !collapsed) {
            SandText(
                copy.t("拖到此处置顶"),
                sand.textSecondary,
                12,
                modifier = Modifier
                    .padding(horizontal = 12.dp, vertical = 6.dp)
                    .fillMaxWidth()
                    .background(sand.fillSecondary, RoundedCornerShape(10.dp))
                    .padding(12.dp)
                    .onGloballyPositioned { dropBounds["pin"] = it.boundsInRoot() },
                textAlign = TextAlign.Center
            )
        }
        Column(
            Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState())
                .semantics { contentDescription = copy.t("Agent list") }
        ) {
            if (!model.loaded) {
                repeat(3) {
                    Box(
                        Modifier
                            .padding(horizontal = 12.dp, vertical = 4.dp)
                            .fillMaxWidth()
                            .height(56.dp)
                            .background(sand.fillSecondary, RoundedCornerShape(8.dp))
                    )
                }
            } else {
                if (projection.pinned.isNotEmpty()) {
                    Column(Modifier.semantics { contentDescription = copy.t("Pinned Agents") }) {
                        if (!collapsed) SandText(copy.t("Pinned Agents"), sand.textTertiary, 11, Modifier.padding(horizontal = 12.dp, vertical = 4.dp))
                        projection.pinned.forEach { agent ->
                            AgentRow(
                                model, agent, collapsed, pinned = true,
                                preview = model.previews[agent.profile.id],
                                dropBounds = dropBounds,
                                onDrop = { point, token -> finishDrop(model, point, dropBounds, token) }
                            )
                        }
                    }
                }
                projection.sections.forEach { section ->
                    if (searching && section.agents.isEmpty()) return@forEach
                    Column(
                        Modifier.onGloballyPositioned { dropBounds["section:${section.id}"] = it.boundsInRoot() }
                    ) {
                        if (!collapsed) {
                            val expanded = searching || !section.isCollapsed
                            Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                                Row(
                                    Modifier.weight(1f).clickable {
                                        val next = model.organization.copy(
                                            sections = model.organization.sections.map {
                                                if (it.id == section.id) it.copy(isCollapsed = !it.isCollapsed) else it
                                            }
                                        )
                                        model.saveOrganization(next)
                                    },
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    com.nuum.feature.shell.chrome.GlyphIcon(
                                        Glyph.ChevronRight,
                                        10.dp,
                                        sand.textSecondary,
                                        Modifier.graphicsLayer { rotationZ = if (expanded) 90f else 0f }
                                    )
                                    SandText(section.name, sand.textPrimary, 13, Modifier.padding(start = 4.dp).weight(1f, fill = false), maxLines = 1)
                                    SandText(section.agents.size.toString(), sand.textTertiary, 11, Modifier.padding(start = 6.dp))
                                }
                                SandText(
                                    "···",
                                    sand.textSecondary,
                                    13,
                                    modifier = Modifier
                                        .semantics { contentDescription = copy.t("Actions for {name}", "name" to section.name) }
                                        .clickable { model.openSectionMenu(section.id) }
                                        .padding(8.dp)
                                )
                            }
                        }
                        val open = collapsed || searching || !section.isCollapsed
                        if (open) {
                            section.agents.forEach { agent ->
                                AgentRow(
                                    model, agent, collapsed, pinned = false,
                                    preview = model.previews[agent.profile.id],
                                    dropBounds = dropBounds,
                                    onDrop = { point, token -> finishDrop(model, point, dropBounds, token) }
                                )
                            }
                            if (!collapsed && section.agents.isEmpty()) {
                                SandText(copy.t("Drag an Agent here"), sand.textTertiary, 11, Modifier.padding(horizontal = 16.dp, vertical = 6.dp))
                            }
                        }
                    }
                }
                Column(Modifier.onGloballyPositioned { dropBounds["unassigned"] = it.boundsInRoot() }) {
                    if (!collapsed && model.organization.sections.isNotEmpty() && merged.isNotEmpty()) {
                        Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 4.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                            SandText(copy.t("Unassigned"), sand.textTertiary, 11)
                            SandText(merged.size.toString(), sand.textTertiary, 11)
                        }
                    }
                    merged.forEach { row ->
                        when (row) {
                            is SidebarRow.Agent -> AgentRow(
                                model, row.agent, collapsed, pinned = false,
                                preview = model.previews[row.agent.profile.id],
                                dropBounds = dropBounds,
                                onDrop = { point, token -> finishDrop(model, point, dropBounds, token) }
                            )
                            is SidebarRow.Work -> WorkRow(model, row.work, collapsed, dropBounds)
                        }
                    }
                }
                if (!hasRows) {
                    val message = if (model.agents.isEmpty() && model.works.isEmpty()) {
                        copy.t("No agents yet")
                    } else {
                        copy.t("No matching agents")
                    }
                    SandText(message, sand.textTertiary, 11, Modifier.padding(16.dp))
                }
                model.notice?.let { AlertLine(copy.t(it), Modifier.padding(horizontal = 12.dp, vertical = 4.dp)) }
            }
        }
        Row(Modifier.fillMaxWidth().padding(4.dp), horizontalArrangement = Arrangement.Start) {
            if (collapsed) {
                IconHit(
                    label = copy.t("New"),
                    title = copy.t("New agent"),
                    glyph = Glyph.Plus,
                    expanded = model.newMenu,
                    onClick = { model.newMenu = !model.newMenu }
                )
            }
            IconHit(copy.t("Settings"), Glyph.Sliders, onClick = { model.openSettings() })
        }
    }
    if (showResize) {
        Box(
            Modifier
                .align(Alignment.CenterEnd)
                .offset(x = 24.dp)
                .width(48.dp)
                .fillMaxHeight()
                .semantics { contentDescription = copy.t("Resize sidebar") }
                .pointerInput(model.layout) {
                    awaitEachGesture {
                        val down = awaitFirstDown()
                        val origin = down.position.x
                        model.beginResize(displaySidebarWidth(model.layout, null, false))
                        val start = model.layoutBefore()
                        drag(down.id) { change ->
                            val deltaDp = ((change.position.x - origin) / density).toInt()
                            model.updateResize((start + deltaDp).coerceIn(SIDEBAR_COLLAPSED, SIDEBAR_MAX_EXPANDED))
                            change.consume()
                        }
                        model.endResize(windowDp)
                    }
                }
        ) {
            Box(
                Modifier
                    .align(Alignment.Center)
                    .width(1.dp)
                    .fillMaxHeight()
                    .background(sand.borderDefault)
            )
        }
    }
    }
}

@Composable
internal fun SidebarOverlays(model: ShellModel) {
    val copy = LocalCopy.current
    if (model.newMenu) {
        ActionMenu(
            label = copy.t("New"),
            onDismiss = { model.newMenu = false },
            entries = listOf(
                MenuEntry(copy.t("Create new Nunu"), Glyph.Plus) {
                    model.newMenu = false
                    model.openCreateNunu()
                },
                MenuEntry(copy.t("Create NunuBar"), Glyph.People) {
                    model.newMenu = false
                    model.openCreateWork()
                }
            )
        )
    }
    SidebarMenus(model)
    model.groupDialog?.let { dialog -> GroupNameDialog(model, dialog.initialName, dialog.sectionId != null) }
}

@Composable
private fun SidebarMenus(model: ShellModel) {
    val copy = LocalCopy.current
    val agentId = model.menuAgentId
    val sectionId = model.menuSectionId
    if (agentId == null && sectionId == null) return
    val entries = if (agentId != null) agentEntries(model, agentId) else sectionEntries(model, sectionId!!)
    ActionMenu(entries, onDismiss = { model.closeMenu() }, label = copy.t("Sidebar actions"))
}

@Composable
private fun agentEntries(model: ShellModel, id: String): List<MenuEntry> {
    val copy = LocalCopy.current
    val clipboard = LocalClipboardManager.current
    if (model.menuGroups) {
        return buildList {
            add(MenuEntry(copy.t("Back"), Glyph.ChevronLeft) { model.menuGroups = false })
            model.organization.sections.forEach { section ->
                add(MenuEntry(section.name, Glyph.Folder, enabled = !model.busy) {
                    model.closeMenu()
                    model.saveOrganization(assignSidebarAgent(model.organization, id, section.id))
                })
            }
            add(MenuEntry(copy.t("Unassigned"), Glyph.Sidebar, enabled = !model.busy) {
                model.closeMenu()
                model.saveOrganization(assignSidebarAgent(model.organization, id, UNASSIGNED_SECTION))
            })
            add(MenuEntry(copy.t("New group…"), Glyph.Plus, enabled = !model.busy, separator = true) {
                model.openNewGroup(id)
            })
        }
    }
    val pinned = id in model.organization.pinnedAgentIds
    return listOf(
        MenuEntry(if (pinned) copy.t("Unpin") else copy.t("Pin"), Glyph.Pin, enabled = !model.busy) {
            model.closeMenu()
            model.pin(id)
        },
        MenuEntry(
            if (model.organization.sections.isEmpty()) copy.t("Move to new group") else copy.t("Move to group"),
            Glyph.Folder,
            enabled = !model.busy
        ) {
            if (model.organization.sections.isEmpty()) model.openNewGroup(id) else model.menuGroups = true
        },
        MenuEntry(copy.t("Edit profile"), Glyph.Edit, separator = true) {
            model.openProfile(id)
        },
        MenuEntry(copy.t("Copy Agent ID"), Glyph.Copy) {
            model.closeMenu()
            val ok = try {
                clipboard.setText(AnnotatedString(id))
                true
            } catch (_: RuntimeException) {
                false
            }
            model.noteCopy(ok)
        }
    )
}

@Composable
private fun sectionEntries(model: ShellModel, sectionId: String): List<MenuEntry> {
    val copy = LocalCopy.current
    val index = model.organization.sections.indexOfFirst { it.id == sectionId }
    val section = model.organization.sections.getOrNull(index) ?: return emptyList()
    return listOf(
        MenuEntry(copy.t("Rename group…"), Glyph.Edit, enabled = !model.busy) {
            model.openRename(section.id, section.name)
        },
        MenuEntry(copy.t("Move up"), Glyph.ArrowUp, enabled = !model.busy && index > 0) {
            model.closeMenu()
            model.saveOrganization(moveSidebarSection(model.organization, index, -1))
        },
        MenuEntry(copy.t("Move down"), Glyph.ArrowDown, enabled = !model.busy && index < model.organization.sections.lastIndex) {
            model.closeMenu()
            model.saveOrganization(moveSidebarSection(model.organization, index, 1))
        },
        MenuEntry(copy.t("Ungroup agents"), Glyph.Ungroup, enabled = !model.busy, separator = true) {
            model.closeMenu()
            model.saveOrganization(removeSidebarSection(model.organization, section.id))
        }
    )
}

@Composable
private fun GroupNameDialog(model: ShellModel, initial: String, rename: Boolean) {
    val copy = LocalCopy.current
    val sand = LocalSand.current
    var name by remember(initial, rename) { mutableStateOf(initial) }
    Box(
        Modifier
            .fillMaxSize()
            .background(sand.scrim)
            .clickable(enabled = !model.busy) { model.closeGroupDialog() },
        contentAlignment = Alignment.Center
    ) {
        Column(
            Modifier
                .padding(16.dp)
                .width(320.dp)
                .background(sand.bgElevated, RoundedCornerShape(18.dp))
                .clickable(onClick = {})
                .padding(16.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                SandText(if (rename) copy.t("Rename group") else copy.t("New group"), sand.textPrimary, 14, Modifier.weight(1f))
                IconHit(copy.t("Close group dialog"), Glyph.Close, enabled = !model.busy, onClick = { model.closeGroupDialog() })
            }
            BasicTextField(
                value = name,
                onValueChange = { if (it.length <= 80) name = it },
                singleLine = true,
                enabled = !model.busy,
                textStyle = TextStyle(color = sand.textPrimary, fontSize = 14.nuum()),
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 12.dp)
                    .border(1.dp, sand.borderDefault, RoundedCornerShape(10.dp))
                    .padding(horizontal = 10.dp, vertical = 8.dp)
                    .testTag("group-name-field")
                    .semantics { contentDescription = copy.t("Group name") },
                decorationBox = { inner ->
                    Box {
                        if (name.isEmpty()) SandText(copy.t("Group name"), sand.textTertiary, 13)
                        inner()
                    }
                }
            )
            model.dialogError?.let { AlertLine(copy.t(it), Modifier.padding(bottom = 8.dp)) }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                PillButton(copy.t("Cancel"), primary = false, enabled = !model.busy, onClick = { model.closeGroupDialog() })
                PillButton(
                    label = if (model.busy) copy.t("Saving…") else copy.t("Save"),
                    primary = true,
                    enabled = !model.busy && name.isNotBlank(),
                    onClick = { model.saveGroup(name) }
                )
            }
        }
    }
}

@Composable
private fun AgentRow(
    model: ShellModel,
    agent: AgentView,
    collapsed: Boolean,
    pinned: Boolean,
    preview: String?,
    dropBounds: MutableMap<String, Rect>,
    onDrop: (Offset, Int) -> Unit
) {
    val copy = LocalCopy.current
    val sand = LocalSand.current
    val selected = model.selectedAgentId == agent.profile.id
    val avatar = if (collapsed) 40.dp else if (pinned) 52.dp else 34.dp
    var origin by remember { mutableStateOf(Offset.Zero) }
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .background(if (selected) sand.fillSelected else androidx.compose.ui.graphics.Color.Transparent)
            .testTag("agent-${agent.profile.id}")
            .onGloballyPositioned {
                origin = it.boundsInRoot().topLeft
                if (pinned) dropBounds["before:${agent.profile.id}"] = it.boundsInRoot()
            }
            .semantics {
                role = Role.Button
                onClick { model.selectAgent(agent.profile.id); true }
                onLongClick { model.openAgentMenu(agent.profile.id); true }
            }
            .agentPointer(
                enabled = !model.busy,
                onClick = { model.selectAgent(agent.profile.id) },
                onLongClick = { model.openAgentMenu(agent.profile.id) },
                onDragStart = {
                    model.dragAgentId = agent.profile.id
                },
                onDragEnd = { delta ->
                    val token = model.dragToken
                    val point = origin + delta
                    onDrop(point, token)
                },
                onDragCancel = { model.cancelDrag() }
            )
            .padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box {
            NunuAvatar(agent.profile.id, agent.profile.avatarColor, agent.profile.avatarShape, agent.profile.avatarMaterial, avatar, fullBody = false)
            if (agent.runtime.status == AgentStatus.RUNNING) {
                Box(
                    Modifier
                        .align(Alignment.BottomEnd)
                        .size(8.dp)
                        .background(sand.fillAccent, RoundedCornerShape(99.dp))
                )
            }
        }
        if (!collapsed) {
            Column(Modifier.weight(1f).padding(horizontal = 8.dp)) {
                SandText(agent.profile.name, sand.textPrimary, 13, weight = FontWeight.Medium, maxLines = 1)
                val subtitle = preview?.takeIf { it.isNotBlank() }
                    ?: agent.profile.description.takeIf { it.isNotBlank() }
                    ?: copy.t("New Agent")
                SandText(subtitle, sand.textSecondary, 12, maxLines = 1)
            }
            Column(horizontalAlignment = Alignment.End) {
                val (key, count) = relativeTimeKey(System.currentTimeMillis(), agent.runtime.lastActivityAt)
                SandText(
                    if (count == null) copy.t(key) else copy.t(key, "count" to count),
                    sand.textTertiary,
                    11
                )
                if (agent.runtime.status == AgentStatus.RUNNING) {
                    SandText(copy.t("Working"), sand.textTertiary, 11)
                }
            }
        }
    }
}

@Composable
private fun WorkRow(
    model: ShellModel,
    work: WorkListItem,
    collapsed: Boolean,
    dropBounds: MutableMap<String, Rect>
) {
    val copy = LocalCopy.current
    val sand = LocalSand.current
    val selected = model.selectedWorkId == work.profile.id
    val members = model.agents.filter { agent ->
        agent.roomMemberships[work.profile.id]?.binding != null ||
            agent.settings.workMembership?.binding?.workId == work.profile.id
    }
    val mark = if (collapsed) 40.dp else 34.dp
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .background(if (selected) sand.fillSelected else androidx.compose.ui.graphics.Color.Transparent)
            .clickable { model.selectWork(work.profile.id) }
            .onGloballyPositioned { dropBounds["work:${work.profile.id}"] = it.boundsInRoot() }
            .padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        if (members.isEmpty()) {
            Box(
                Modifier
                    .size(mark)
                    .background(sand.bgSecondary, RoundedCornerShape(11.dp))
                    .border(1.dp, sand.borderSubtle, RoundedCornerShape(11.dp)),
                contentAlignment = Alignment.Center
            ) {
                SandText(work.profile.name.take(1).uppercase(), sand.textPrimary, 13, weight = FontWeight.SemiBold)
            }
        } else {
            Box(Modifier.size(mark)) {
                members.take(4).forEachIndexed { index, member ->
                    NunuAvatar(
                        member.profile.id,
                        member.profile.avatarColor,
                        member.profile.avatarShape,
                        member.profile.avatarMaterial,
                        mark / 2,
                        fullBody = false,
                        modifier = Modifier.align(
                            when (index) {
                                0 -> Alignment.TopStart
                                1 -> Alignment.TopEnd
                                2 -> Alignment.BottomStart
                                else -> Alignment.BottomEnd
                            }
                        )
                    )
                }
            }
        }
        if (!collapsed) {
            Column(Modifier.weight(1f).padding(horizontal = 8.dp)) {
                SandText(work.profile.name, sand.textPrimary, 13, weight = FontWeight.Medium, maxLines = 1)
                val subtitle = work.preview?.takeIf { it.isNotBlank() }
                    ?: work.profile.description.takeIf { it.isNotBlank() }
                    ?: copy.t("New Work")
                SandText(subtitle, sand.textSecondary, 12, maxLines = 1)
            }
            val (key, count) = relativeTimeKey(System.currentTimeMillis(), work.lastActivityAt)
            SandText(if (count == null) copy.t(key) else copy.t(key, "count" to count), sand.textTertiary, 11)
        }
    }
}

private fun finishDrop(model: ShellModel, point: Offset, bounds: Map<String, Rect>, token: Int) {
    val agentId = model.dragAgentId
    model.dragAgentId = null
    if (agentId == null || token != model.dragToken) return
    val hit = bounds.filterValues { it.contains(point) }.minByOrNull { it.value.width * it.value.height }?.key ?: return
    when {
        hit.startsWith("before:") -> {
            val before = hit.removePrefix("before:")
            if (before != agentId) model.saveOrganization(reorderSidebarPin(model.organization, agentId, before))
        }
        hit.startsWith("work:") -> model.moveAgentToWork(agentId, hit.removePrefix("work:"))
        hit == "pin" -> {
            if (agentId !in model.organization.pinnedAgentIds) model.pin(agentId)
        }
        hit.startsWith("section:") -> model.saveOrganization(assignSidebarAgent(model.organization, agentId, hit.removePrefix("section:")))
        hit == "unassigned" -> model.saveOrganization(assignSidebarAgent(model.organization, agentId, UNASSIGNED_SECTION))
    }
}

private fun Modifier.agentPointer(
    enabled: Boolean,
    onClick: () -> Unit,
    onLongClick: () -> Unit,
    onDragStart: () -> Unit,
    onDragEnd: (Offset) -> Unit,
    onDragCancel: () -> Unit
): Modifier = pointerInput(enabled) {
    if (!enabled) return@pointerInput
    awaitEachGesture {
        val down = awaitFirstDown()
        val released = withTimeoutOrNull(300) { waitForUpOrCancellation() }
        if (released != null) {
            onClick()
            return@awaitEachGesture
        }
        var dragged = false
        val slop = awaitTouchSlopOrCancellation(down.id) { change, _ ->
            dragged = true
            change.consume()
        }
        if (!dragged || slop == null) {
            onLongClick()
            return@awaitEachGesture
        }
        onDragStart()
        var delta = Offset.Zero
        val completed = drag(slop.id) { change ->
            delta += change.positionChange()
            change.consume()
        }
        if (completed) onDragEnd(delta) else onDragCancel()
    }
}

private fun ShellModel.layoutBefore(): Int = displaySidebarWidth(layout, null, false)
