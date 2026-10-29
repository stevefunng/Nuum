package com.nuum.feature.settings

import com.nuum.contracts.Clock
import com.nuum.contracts.ProactivePort
import com.nuum.contracts.SecretWriter
import com.nuum.contracts.SettingsPort

/**
 * Ports this feature is allowed to call. [SecretWriter] writes API keys and
 * does not return plaintext. There is no account backend in the PoC.
 */
data class SettingsDependencies(
    val settings: SettingsPort,
    val secrets: SecretWriter,
    val proactive: ProactivePort,
    val clock: Clock = Clock { System.currentTimeMillis() }
)
