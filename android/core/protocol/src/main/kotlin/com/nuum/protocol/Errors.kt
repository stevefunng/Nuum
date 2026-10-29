package com.nuum.protocol

import kotlinx.serialization.json.JsonElement

/**
 * Numeric codes from `packages/protocol/src/errors.ts`.
 * 1001 and 2005–2007 are unused on purpose.
 * [DesktopErrorCode.WINDOW] is the code only; desktop window methods are not ported.
 */
object KernelErrorCode {
    const val INTERNAL = 1000
    const val TURN_BUSY = 1002
    const val CANCELLED = 1003
    const val MODEL = 1004
    const val TOOL = 1005
    const val SANDBOX = 1006
    const val INVALID = 1007
}

object HostErrorCode {
    const val AGENT_NOT_FOUND = 2001
    const val AGENT_BUSY = 2002
    const val NO_WORKSPACE = 2003
    const val NO_API_KEY = 2004
    const val KERNEL_DOWN = 2008
    const val DATA_DIR_LOCKED = 2009
    const val WORK_NOT_FOUND = 2010
    const val WORK_CONFLICT = 2011
    const val WORK_FORBIDDEN = 2012
}

object DesktopErrorCode {
    const val SECRET_STORE = 3001
    const val FOLDER_PICK = 3002
    const val WINDOW = 3003
}

class RpcError(
    val code: Int,
    message: String,
    val data: JsonElement? = null
) : Exception(message)
