package com.nuum.feature.work

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

internal const val TAG_DISCOVER_CARD = "discover-card"
internal const val TAG_CATALOG_KIND = "catalog-kind"
internal const val TAG_CATALOG_NAME = "catalog-name"
internal const val TAG_CATALOG_PATH = "catalog-path"
internal const val TAG_CATALOG_COMMANDS = "catalog-commands"
internal const val TAG_CATALOG_SUBMIT = "catalog-submit"

@Composable
internal fun CapabilityDialog(
    controller: WorkController,
    wide: Boolean,
    onClose: () -> Unit,
) {
    Dialog(onDismissRequest = onClose, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(WorkColors.scrim)
                    .clickable(onClick = onClose),
            )
            Column(
                modifier = Modifier
                    .then(if (wide) Modifier.widthIn(max = 560.dp) else Modifier.fillMaxSize())
                    .background(WorkColors.bgElevated, if (wide) WorkRadius2xl else androidx.compose.foundation.shape.RoundedCornerShape(0.dp))
                    .pointerInput(Unit) { detectTapGestures { } }
                    .verticalScroll(rememberScrollState())
                    .padding(20.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                DialogHeader(
                    title = stringResource(R.string.work_capabilities),
                    subtitle = stringResource(R.string.work_catalog_subtitle),
                    onClose = onClose,
                )
                CapabilityBody(controller = controller, onClose = onClose)
            }
        }
    }
}

@Composable
internal fun DialogHeader(title: String, subtitle: String?, onClose: () -> Unit) {
    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Column(modifier = Modifier.weight(1f)) {
            Text(title, color = WorkColors.textPrimary, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
            if (subtitle != null) {
                Text(subtitle, color = WorkColors.textSecondary, fontSize = 12.sp)
            }
        }
        WorkIconButton(label = stringResource(R.string.work_close_dialog), onClick = onClose) {
            Text("×", color = WorkColors.textSecondary, fontSize = 18.sp)
        }
    }
}

@Composable
private fun CapabilityBody(controller: WorkController, onClose: () -> Unit) {
    var tab by remember { mutableStateOf("discover") }
    val source = stringResource(R.string.work_capability_source)
    Row(
        modifier = Modifier.semantics { contentDescription = source },
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        KindChip(
            text = stringResource(R.string.work_discover),
            selected = tab == "discover",
            onClick = { tab = "discover" },
        )
        KindChip(
            text = stringResource(R.string.work_import_local),
            selected = tab == "local",
            onClick = { tab = "local" },
        )
    }
    if (tab == "discover") {
        DiscoverPage(onImport = { tab = "local" })
    } else {
        ImportPage(controller = controller, onClose = onClose)
    }
}

@Composable
private fun DiscoverPage(onImport: () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(stringResource(R.string.work_collection), color = WorkColors.textTertiary, fontSize = 11.sp)
            Text(stringResource(R.string.work_coming_soon), color = WorkColors.textTertiary, fontSize = 11.sp)
        }
        DiscoverCard(
            eyebrow = stringResource(R.string.work_know_how),
            title = stringResource(R.string.work_skills),
            body = stringResource(R.string.work_thoughtful) + "\n" + stringResource(R.string.work_ready_next),
        )
        DiscoverCard(
            eyebrow = stringResource(R.string.work_hands_on),
            title = stringResource(R.string.work_cli_tools),
            body = stringResource(R.string.work_familiar) + "\n" + stringResource(R.string.work_possibility),
        )
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable(onClick = onImport)
                .padding(vertical = 8.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(stringResource(R.string.work_already), color = WorkColors.textPrimary, fontWeight = FontWeight.SemiBold, fontSize = 13.sp)
                Text(stringResource(R.string.work_bring_local), color = WorkColors.textSecondary, fontSize = 12.sp)
            }
            Text(stringResource(R.string.work_import_local) + " +", color = WorkColors.textPrimary, fontSize = 13.sp)
        }
    }
}

@Composable
private fun DiscoverCard(eyebrow: String, title: String, body: String) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .testTag(TAG_DISCOVER_CARD)
            .background(WorkColors.bgEditor, WorkRadiusLg)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(eyebrow, color = WorkColors.textTertiary, fontSize = 11.sp)
        Text(title, color = WorkColors.textPrimary, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
        Text(body, color = WorkColors.textSecondary, fontSize = 13.sp)
        Text(stringResource(R.string.work_presets), color = WorkColors.textTertiary, fontSize = 12.sp)
    }
}

@Composable
private fun ImportPage(controller: WorkController, onClose: () -> Unit) {
    var kind by remember { mutableStateOf(CatalogKind.SKILL) }
    var name by remember { mutableStateOf("") }
    var path by remember { mutableStateOf("") }
    var commands by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val missingTool = stringResource(R.string.work_enter_tool)
    val failed = stringResource(R.string.work_import_failed)
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            CATALOG_KINDS.forEach { item ->
                KindChip(
                    text = kindLabel(item),
                    selected = kind == item,
                    enabled = !busy,
                    tag = TAG_CATALOG_KIND,
                    onClick = {
                        kind = item
                        path = ""
                        commands = ""
                        error = null
                    },
                )
            }
        }
        FieldLabel(stringResource(R.string.work_name))
        WorkInput(
            value = name,
            onValueChange = { name = it },
            placeholder = if (kind == CatalogKind.SKILL) {
                stringResource(R.string.work_skill_placeholder)
            } else {
                stringResource(R.string.work_short_name)
            },
            label = stringResource(R.string.work_name),
            enabled = !busy,
            tag = TAG_CATALOG_NAME,
        )
        FieldLabel(pathLabel(kind))
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            WorkInput(
                value = path,
                onValueChange = { path = it },
                placeholder = pathPlaceholder(kind),
                label = pathLabel(kind),
                enabled = !busy,
                tag = TAG_CATALOG_PATH,
                modifier = Modifier.weight(1f),
            )
            if (kind == CatalogKind.SKILL || kind == CatalogKind.KNOWLEDGE) {
                WorkTextButton(
                    text = stringResource(R.string.work_browse),
                    enabled = !busy,
                    onClick = {
                        scope.launch {
                            val directory = controller.pickDirectory() ?: return@launch
                            path = if (kind == CatalogKind.SKILL) skillManifestPath(directory) else directory
                            if (name.isBlank()) name = directoryName(directory)
                        }
                    },
                )
            }
        }
        if (kind == CatalogKind.CLI) {
            FieldLabel(stringResource(R.string.work_allowed_subcommands))
            WorkInput(
                value = commands,
                onValueChange = { commands = it },
                placeholder = stringResource(R.string.work_subcommands_placeholder),
                label = stringResource(R.string.work_allowed_subcommands),
                enabled = !busy,
                tag = TAG_CATALOG_COMMANDS,
            )
        }
        Text(importNote(kind), color = WorkColors.textSecondary, fontSize = 12.sp)
        if (error != null) WorkAlert(error!!)
        val submit = if (busy) stringResource(R.string.work_importing) else stringResource(R.string.work_add_to_work)
        WorkTextButton(
            text = submit,
            primary = true,
            enabled = !busy && name.isNotBlank() && path.isNotBlank(),
            modifier = Modifier.testTag(TAG_CATALOG_SUBMIT),
            onClick = {
                val entry = catalogInput(kind, name, path, commands)
                if (entry == null) {
                    error = missingTool
                    return@WorkTextButton
                }
                scope.launch {
                    busy = true
                    error = null
                    try {
                        controller.addCatalog(entry)
                        onClose()
                    } catch (cancelled: CancellationException) {
                        throw cancelled
                    } catch (failure: Exception) {
                        error = failure.message?.takeIf { it.isNotBlank() } ?: failed
                        busy = false
                    }
                }
            },
        )
    }
}

@Composable
private fun KindChip(
    text: String,
    selected: Boolean,
    onClick: () -> Unit,
    enabled: Boolean = true,
    tag: String? = null,
) {
    Text(
        text = text,
        color = if (selected) WorkColors.textOnPrimary else WorkColors.textPrimary,
        fontSize = 13.sp,
        fontWeight = FontWeight.SemiBold,
        modifier = Modifier
            .then(if (tag != null) Modifier.testTag(tag) else Modifier)
            .background(if (selected) WorkColors.fillPrimary else WorkColors.fillSecondary, WorkRadiusFull)
            .semantics {
                role = Role.Button
                this.selected = selected
            }
            .clickable(enabled = enabled, onClick = onClick, role = Role.Button)
            .padding(horizontal = 12.dp, vertical = 8.dp),
    )
}

@Composable
internal fun WorkInput(
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    label: String,
    enabled: Boolean,
    tag: String,
    modifier: Modifier = Modifier,
) {
    BasicTextField(
        value = value,
        onValueChange = onValueChange,
        enabled = enabled,
        singleLine = true,
        textStyle = TextStyle(color = WorkColors.textPrimary, fontSize = 14.sp),
        cursorBrush = SolidColor(WorkColors.textPrimary),
        modifier = modifier
            .fillMaxWidth()
            .testTag(tag)
            .background(WorkColors.bgInput, WorkRadiusLg)
            .semantics { contentDescription = label }
            .padding(horizontal = 12.dp, vertical = 10.dp),
        decorationBox = { inner ->
            Box {
                if (value.isEmpty()) Text(placeholder, color = WorkColors.textTertiary, fontSize = 14.sp)
                inner()
            }
        },
    )
}

@Composable
private fun FieldLabel(text: String) {
    Text(text, color = WorkColors.textSecondary, fontSize = 12.sp)
}

@Composable
private fun kindLabel(kind: CatalogKind): String = stringResource(
    when (kind) {
        CatalogKind.SKILL -> R.string.work_skill
        CatalogKind.CLI -> R.string.work_cli
        CatalogKind.KNOWLEDGE -> R.string.work_knowledge
        CatalogKind.LOCAL_TOOL -> R.string.work_local_tools
    },
)

@Composable
private fun pathLabel(kind: CatalogKind): String = stringResource(
    when (kind) {
        CatalogKind.SKILL -> R.string.work_skill_manifest
        CatalogKind.CLI -> R.string.work_executable
        CatalogKind.KNOWLEDGE -> R.string.work_knowledge_folder
        CatalogKind.LOCAL_TOOL -> R.string.work_tool_names
    },
)

@Composable
private fun pathPlaceholder(kind: CatalogKind): String = when (kind) {
    CatalogKind.SKILL -> stringResource(R.string.work_path_skill)
    CatalogKind.CLI -> stringResource(R.string.work_path_cli)
    CatalogKind.KNOWLEDGE -> stringResource(R.string.work_path_knowledge)
    CatalogKind.LOCAL_TOOL -> stringResource(R.string.work_tool_names_placeholder)
}

@Composable
private fun importNote(kind: CatalogKind): String = stringResource(
    when (kind) {
        CatalogKind.KNOWLEDGE -> R.string.work_note_knowledge
        CatalogKind.SKILL -> R.string.work_note_skill
        CatalogKind.CLI -> R.string.work_note_cli
        CatalogKind.LOCAL_TOOL -> R.string.work_note_local_tool
    },
)
