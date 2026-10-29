package com.nuum.storage

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.nuum.storage.projection.NuumDatabase
import java.io.File
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
abstract class StorageRobolectricTest {
    protected fun <T> withStore(
        beforeCommit: () -> Unit = {},
        block: suspend (FileAgentStore) -> T
    ): T = runBlocking {
        val store = newStore(beforeCommit)
        try {
            block(store)
        } finally {
            store.close()
        }
    }
}

internal fun newStore(beforeCommit: () -> Unit = {}): FileAgentStore {
    val context = ApplicationProvider.getApplicationContext<Context>()
    val root = File(context.cacheDir, "nuum-${UUID.randomUUID()}").apply { mkdirs() }
    val database = Room.inMemoryDatabaseBuilder(context, NuumDatabase::class.java)
        .allowMainThreadQueries()
        .build()
    val preferences = File(context.cacheDir, "ui-${UUID.randomUUID()}.preferences_pb")
    return FileAgentStore(root, database, preferences, beforeCommit)
}
