package com.nuum.tools

internal fun builtinTools(): List<Tool> = listOf(
    ReadTool,
    WriteTool,
    StrReplaceTool,
    MultiStrReplaceTool,
    DeleteTool,
    LsTool,
    GlobTool,
    GrepTool,
    ShellTool,
    NetworkTool,
    ExternalTool
)
