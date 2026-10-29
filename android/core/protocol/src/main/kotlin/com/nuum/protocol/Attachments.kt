package com.nuum.protocol

import kotlinx.serialization.Serializable

const val MAX_ATTACHMENT_BYTES = 10 * 1024 * 1024
const val MAX_ATTACHMENTS = 5

/** Mac inlines this 20 MiB ceiling in host and ui. Android keeps one named constant. */
const val MAX_ATTACHMENT_TOTAL_BYTES = 20 * 1024 * 1024

/** `ceil(MAX_ATTACHMENT_BYTES / 3) * 4`, the Zod max on the base64 `data` string. */
const val MAX_ATTACHMENT_BASE64_CHARS = ((MAX_ATTACHMENT_BYTES + 2) / 3) * 4

const val ATTACHMENT_COUNT_MESSAGE = "At most 5 attachments per message."
const val ATTACHMENT_SIZE_MESSAGE = "Each attachment must be 10 MB or smaller."
const val ATTACHMENT_TOTAL_MESSAGE = "Attachments must total 20 MB or less."

val IMAGE_MIME_TYPES: Set<String> = setOf(
    "image/png",
    "image/jpeg",
    "image/gif",
    "image/webp"
)

private val BASE64_DATA = Regex("""^[A-Za-z0-9+/]*={0,2}$""")

/**
 * Wire shape of an upload. Field name is `data` (base64), matching
 * `packages/protocol/src/attachments.ts`.
 */
@Serializable
data class AttachmentUpload(
    val name: String,
    val mimeType: String,
    val data: String
)

@Serializable
data class UserAttachment(
    val name: String,
    val path: String,
    val mimeType: String,
    val size: Int,
    val text: String? = null
)

fun validateAttachmentUpload(upload: AttachmentUpload) {
    val issues = mutableListOf<ProtocolIssue>()
    if (upload.name.isEmpty() || upload.name.length > 255) {
        issues += ProtocolIssue(listOf("name"), "String must contain at least 1 character(s)")
    }
    if (upload.mimeType.length > 120) {
        issues += ProtocolIssue(listOf("mimeType"), "String must contain at most 120 character(s)")
    }
    val data = upload.data
    if (!BASE64_DATA.matches(data) || data.length > MAX_ATTACHMENT_BASE64_CHARS) {
        issues += ProtocolIssue(listOf("data"), "Invalid")
    } else if (data.length % 4 != 0) {
        issues += ProtocolIssue(listOf("data"), "Invalid base64 length")
    }
    if (issues.isNotEmpty()) throw ProtocolParseException(issues)
}

/**
 * Count, then per-file, then total. Messages match the Mac host and the attachment screen.
 * [sizes] are decoded byte lengths, not base64 lengths.
 */
fun attachmentLimitError(sizes: List<Long>): String? {
    if (sizes.size > MAX_ATTACHMENTS) return ATTACHMENT_COUNT_MESSAGE
    if (sizes.any { it > MAX_ATTACHMENT_BYTES }) return ATTACHMENT_SIZE_MESSAGE
    if (sizes.sum() > MAX_ATTACHMENT_TOTAL_BYTES) return ATTACHMENT_TOTAL_MESSAGE
    return null
}

fun requireAttachmentLimits(sizes: List<Long>) {
    val error = attachmentLimitError(sizes) ?: return
    throw IllegalArgumentException(error)
}

/** Conservative defaults for manually entered model ids. Unknown ids use file tools. */
fun supportsImageInput(model: ModelRef): Boolean {
    if (model.provider == ProviderId.DEEPSEEK) return false
    if (model.provider == ProviderId.ANTHROPIC) {
        return ANTHROPIC_IMAGE.containsMatchIn(model.model)
    }
    return OPENAI_IMAGE.containsMatchIn(model.model)
}

private val ANTHROPIC_IMAGE = Regex("""^claude-(?:3|sonnet-4|opus-4|haiku-4)""", RegexOption.IGNORE_CASE)
private val OPENAI_IMAGE = Regex(
    """^(?:gpt-4o|gpt-4\.1|gpt-4-turbo|gpt-5|o1(?!-mini|-preview)|o3(?!-mini)|o4)""",
    RegexOption.IGNORE_CASE
)
