package com.nuum.tools

import com.nuum.contracts.KernelErrorCode
import com.nuum.contracts.NuumException

internal fun stringField(
    input: Map<String, Any?>,
    key: String,
    optional: Boolean = false,
    allowEmpty: Boolean = false
): String? {
    val value = input[key]
    if (value == null) {
        if (optional) return null
        throw invalidString(key, allowEmpty)
    }
    if (value !is String || (!allowEmpty && value.isEmpty())) {
        throw invalidString(key, allowEmpty)
    }
    return value
}

internal fun booleanField(input: Map<String, Any?>, key: String): Boolean? {
    val value = input[key] ?: return null
    if (value !is Boolean) {
        throw NuumException(KernelErrorCode.INVALID, "$key must be a boolean.")
    }
    return value
}

internal fun integerField(input: Map<String, Any?>, key: String, min: Int): Int? {
    val value = input[key] ?: return null
    val integer = asInteger(value)
    if (integer == null || integer < min || integer > Int.MAX_VALUE) {
        throw NuumException(KernelErrorCode.INVALID, "$key must be an integer >= $min.")
    }
    return integer.toInt()
}

internal fun enumField(
    input: Map<String, Any?>,
    key: String,
    values: List<String>,
    fallback: String
): String {
    val value = input[key] ?: fallback
    if (value !is String || value !in values) {
        throw NuumException(
            KernelErrorCode.INVALID,
            "$key must be one of: ${values.joinToString(", ")}."
        )
    }
    return value
}

private fun invalidString(key: String, allowEmpty: Boolean): NuumException {
    val qualifier = if (allowEmpty) "string" else "non-empty string"
    return NuumException(KernelErrorCode.INVALID, "$key must be a $qualifier.")
}

private fun asInteger(value: Any): Long? = when (value) {
    is Byte -> value.toLong()
    is Short -> value.toLong()
    is Int -> value.toLong()
    is Long -> value
    is Double -> if (value.isFinite() && value % 1.0 == 0.0) value.toLong() else null
    is Float -> if (value.isFinite() && value % 1.0f == 0.0f) value.toLong() else null
    else -> null
}
