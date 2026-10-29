package com.nuum.graph

import com.nuum.contracts.IdentityContext

/** PoC identity. Transcript records do not gain a user field. */
object LocalOnly : IdentityContext {
    override val userId: String? = null
}
