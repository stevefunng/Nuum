package com.nuum.tools

import com.nuum.contracts.ToolDefinition
import com.nuum.contracts.ToolExecutionResult

internal interface Tool {
    val definition: ToolDefinition
    suspend fun execute(input: Map<String, Any?>, sandbox: RunSandbox): ToolExecutionResult
}

class ToolRegistry internal constructor(tools: List<Tool>) {
    private val tools = LinkedHashMap<String, Tool>()

    init {
        for (tool in tools) this.tools[tool.definition.name] = tool
    }

    internal fun get(name: String): Tool? = tools[name]

    /**
     * 不给 names 是「全都要」，给空数组是「一个都不要」。这两者必须分开：混同的话
     * 「这个 run 不许用本地工具」会被静默解释成「本地工具全放开」。
     */
    fun list(names: List<String>? = null): List<ToolDefinition> {
        val all = tools.values.map { it.definition }
        if (names == null) return all
        return all.filter { it.name in names }
    }

    companion object {
        fun builtin(): ToolRegistry = ToolRegistry(builtinTools())
    }
}
