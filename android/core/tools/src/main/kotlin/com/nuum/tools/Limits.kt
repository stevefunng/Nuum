package com.nuum.tools

internal const val MAX_READ_CHARS = 30_000
internal const val MAX_TREE_CHARS = 20_000
internal const val MAX_DIFF_CHARS = 12_000
internal const val MAX_GLOB_RESULTS = 500
internal const val MAX_GREP_OUTPUT = 500_000

/** Shell, request_network, and external_operation all return this sentence. */
const val POC_NOT_IMPLEMENTED = "This Android PoC does not implement this tool."

internal const val OUTSIDE_ROOT = "Path is outside the allowed local execution root."
