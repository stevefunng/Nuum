package com.nuum

import android.content.pm.ApplicationInfo
import androidx.test.core.app.ApplicationProvider
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.xmlpull.v1.XmlPullParser

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = NuumApplication::class)
class ManifestSecurityTest {
    @Test
    fun backupIsOffCleartextIsOffAndSecretsAreExcluded() {
        val app = ApplicationProvider.getApplicationContext<NuumApplication>()
        @Suppress("DEPRECATION")
        val info = app.packageManager.getApplicationInfo(app.packageName, 0)
        assertEquals(0, info.flags and ApplicationInfo.FLAG_ALLOW_BACKUP)
        assertEquals(0, info.flags and ApplicationInfo.FLAG_USES_CLEARTEXT_TRAFFIC)
        assertEquals(36, info.targetSdkVersion)

        val manifest = File("src/main/AndroidManifest.xml").readText()
        assertTrue(manifest.contains("android:allowBackup=\"false\""))
        assertTrue(manifest.contains("android:dataExtractionRules=\"@xml/data_extraction_rules\""))
        assertTrue(manifest.contains("android:fullBackupContent=\"@xml/backup_rules\""))
        assertTrue(manifest.contains("android:networkSecurityConfig=\"@xml/network_security_config\""))
        assertTrue(manifest.contains("android:usesCleartextTraffic=\"false\""))

        val rules = xmlText(app, R.xml.data_extraction_rules)
        assertTrue(rules.contains("secrets.bin"))
        assertTrue(rules.contains("no_backup"))
        val backup = xmlText(app, R.xml.backup_rules)
        assertTrue(backup.contains("secrets.bin"))
        val network = xmlText(app, R.xml.network_security_config)
        assertTrue(network.contains("cleartextTrafficPermitted"))
        assertTrue(network.contains("false"))
    }

    private fun xmlText(app: NuumApplication, resId: Int): String {
        val parser = app.resources.getXml(resId)
        return buildString {
            var event = parser.eventType
            while (event != XmlPullParser.END_DOCUMENT) {
                if (event == XmlPullParser.START_TAG) {
                    append(parser.name)
                    for (index in 0 until parser.attributeCount) {
                        append(' ')
                        append(parser.getAttributeName(index))
                        append('=')
                        append(parser.getAttributeValue(index))
                    }
                    append('\n')
                }
                event = parser.next()
            }
        }
    }
}
