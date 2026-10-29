package com.nuum.graph

import android.app.Application
import android.content.Intent
import androidx.test.core.app.ApplicationProvider
import com.nuum.contracts.NuumPaths
import java.io.File
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class DesktopPortTest {
    @Test
    fun cancelAndMissingActivityReturnWithoutCrashing() = runBlocking {
        val app = ApplicationProvider.getApplicationContext<Application>()
        val port = AndroidDesktopPort(app)
        assertNull(port.pickDirectory())
        assertTrue(port.pickFiles().isEmpty())
        port.openAttachment("")
        port.share("")
        port.openAttachment("/no/such/attachment")
        port.share("/no/such/attachment")
    }

    @Test
    fun secretsPathIsNotOpenedOrShared() = runBlocking {
        val app = ApplicationProvider.getApplicationContext<Application>()
        val port = AndroidDesktopPort(app)
        val secrets = File(app.noBackupFilesDir, NuumPaths.secretsFileName())
        secrets.writeBytes(byteArrayOf(7, 7, 7))
        port.openAttachment(secrets.absolutePath)
        port.share(secrets.absolutePath)
        port.openAttachment(app.noBackupFilesDir.absolutePath)
        assertNull(startedIntent(app))
        assertTrue(secrets.isFile)
    }

    private fun startedIntent(app: Application): Intent? = Shadows.shadowOf(app).nextStartedActivity
}
