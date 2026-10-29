package com.nuum.security

import android.app.Instrumentation
import android.os.Bundle
import org.junit.runner.Description
import org.junit.runner.JUnitCore
import org.junit.runner.Request
import org.junit.runner.notification.Failure
import org.junit.runner.notification.RunListener

/**
 * Runs [KeystoreSecretStoreInstrumentedTest] on a device.
 * `androidx.test:runner` is not in the version catalog, so this stays on [org.junit].
 *
 * Local device:
 * `./gradlew :core:security:connectedDebugAndroidTest`
 * CI does not boot an emulator.
 */
class SecretStoreInstrumentation : Instrumentation() {
    override fun onCreate(arguments: Bundle?) {
        super.onCreate(arguments)
        instance = this
        start()
    }

    override fun onStart() {
        val request = Request.classes(KeystoreSecretStoreInstrumentedTest::class.java)
        val total = request.runner.testCount()
        var index = 0
        val core = JUnitCore()
        core.addListener(object : RunListener() {
            override fun testStarted(description: Description) {
                index += 1
                sendStatus(1, status(description).apply {
                    putInt("current", index)
                    putInt("numtests", total)
                })
            }

            override fun testFinished(description: Description) {
                sendStatus(0, status(description))
            }

            override fun testFailure(failure: Failure) {
                sendStatus(-2, status(failure.description).apply {
                    putString("stack", failure.trace)
                    putString("stream", failure.trace)
                })
            }

            override fun testIgnored(description: Description) {
                sendStatus(-4, status(description))
            }
        })
        val result = core.run(request)
        finish(if (result.wasSuccessful()) 0 else 1, Bundle().apply {
            putString("stream", "${result.runCount} tests, ${result.failureCount} failed")
        })
    }

    private fun status(description: Description): Bundle = Bundle().apply {
        putString("class", description.className)
        putString("test", description.methodName)
        putString("id", "${description.className}#${description.methodName}")
    }

    companion object {
        lateinit var instance: SecretStoreInstrumentation
            private set
    }
}
