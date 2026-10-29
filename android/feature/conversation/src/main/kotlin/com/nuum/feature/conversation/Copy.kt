package com.nuum.feature.conversation

import androidx.annotation.StringRes
import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource

internal fun formatCopy(template: String, values: Map<String, String>): String {
    var result = template
    for ((key, value) in values) result = result.replace("{$key}", value)
    return result
}

@Composable
internal fun copy(@StringRes id: Int, vararg values: Pair<String, String>): String {
    return formatCopy(stringResource(id), values.toMap())
}

@Composable
internal fun copy(key: CopyKey): String = stringResource(
    when (key) {
        CopyKey.AtMost5 -> R.string.at_most_5
        CopyKey.TooLarge -> R.string.each_attachment_10
        CopyKey.TotalTooLarge -> R.string.attachments_total_20
        CopyKey.ReadFailed -> R.string.could_not_read_attachment
        CopyKey.Reading -> R.string.reading_attachments
        CopyKey.Stopped -> R.string.stopped
        CopyKey.HostError -> R.string.host_error
        CopyKey.NoImageSupport -> R.string.no_image_support
    }
)
