package com.nuum

import android.app.Application
import com.nuum.graph.AppGraph

/** Process entry. One [AppGraph] is built here and reused by [MainActivity]. */
class NuumApplication : Application() {
    lateinit var graph: AppGraph
        private set

    override fun onCreate() {
        super.onCreate()
        graph = AppGraph(this)
    }
}
