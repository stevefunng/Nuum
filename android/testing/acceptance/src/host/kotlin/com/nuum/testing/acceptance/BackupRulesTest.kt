package com.nuum.testing.acceptance

import java.io.File
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Scenario 11. Reads the backup rules from source. Does not run `adb backup`
 * and does not upload anything.
 *
 * Working directory is the `:app` module, because this source set is compiled
 * into `:app`'s unit tests.
 */
class BackupRulesTest {
    @Test
    fun extractionRulesExcludeSecretsAndNuumFiles() {
        val manifest = File("src/main/AndroidManifest.xml").readText()
        assertTrue(manifest.contains("android:allowBackup=\"false\""))
        assertTrue(manifest.contains("android:dataExtractionRules=\"@xml/data_extraction_rules\""))
        assertTrue(manifest.contains("android:fullBackupContent=\"@xml/backup_rules\""))

        val extraction = File("src/main/res/xml/data_extraction_rules.xml").readText()
        assertTrue(extraction.contains("<cloud-backup>"))
        assertTrue(extraction.contains("<device-transfer>"))
        assertTrue(extraction.contains("path=\"no_backup\""))
        assertTrue(extraction.contains("path=\"no_backup/secrets.bin\""))
        assertTrue(extraction.contains("domain=\"file\" path=\"nuum\""))
        assertFalse(extraction.contains("path=\"secrets.bin\" />") && !extraction.contains("no_backup/secrets.bin"))

        val legacy = File("src/main/res/xml/backup_rules.xml").readText()
        assertTrue(legacy.contains("path=\"no_backup/secrets.bin\""))
        assertTrue(legacy.contains("domain=\"file\" path=\"nuum\""))
        assertTrue(legacy.contains("path=\"no_backup\""))
    }
}
