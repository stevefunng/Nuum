package com.nuum.agent

/**
 * OS line for the uncached environment segment.
 * [HostRuntime] takes the string so tests do not touch Android stubs.
 * AppGraph should pass this value.
 */
fun androidOsLabel(): String {
    val release = android.os.Build.VERSION.RELEASE ?: "unknown"
    val sdk = android.os.Build.VERSION.SDK_INT
    return "Android $release (API $sdk)"
}
