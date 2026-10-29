package com.nuum.graph

import com.nuum.contracts.SyncPort

/** PoC sync. Methods do nothing. Later units are an agent directory and a work timeline. */
object NoSync : SyncPort {
    override suspend fun pushAgent(agentId: String) = Unit

    override suspend fun pullAgent(agentId: String) = Unit

    override suspend fun pushWork(workId: String) = Unit

    override suspend fun pullWork(workId: String) = Unit
}
