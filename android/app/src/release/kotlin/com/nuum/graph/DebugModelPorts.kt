package com.nuum.graph

import android.content.Context
import com.nuum.contracts.ModelPort
import com.nuum.model.OkHttpModelPort

/**
 * Release builds have no fake model. The debug source set is the only place
 * that reads `nuum.fakeModel`.
 */
internal object DebugModelPorts {
    fun select(@Suppress("UNUSED_PARAMETER") context: Context): ModelPort = OkHttpModelPort()
}
