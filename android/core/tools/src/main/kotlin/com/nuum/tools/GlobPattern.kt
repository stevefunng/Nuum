package com.nuum.tools

internal fun matchesGlob(relativePath: String, pattern: String): Boolean {
    val effective = if (pattern.startsWith("**/")) pattern else "**/$pattern"
    return globRegex(effective).matches(relativePath)
}

/** ripgrep `--glob`: a pattern with no slash matches the file name in any directory. */
internal fun matchesRgGlob(relativePath: String, pattern: String): Boolean {
    val effective = if (pattern.contains('/')) pattern else "**/$pattern"
    return globRegex(effective).matches(relativePath)
}

private fun globRegex(pattern: String): Regex {
    val body = StringBuilder("^")
    var index = 0
    while (index < pattern.length) {
        if (pattern.startsWith("**/", index)) {
            body.append("(?:.*/)?")
            index += 3
            continue
        }
        if (pattern.startsWith("**", index)) {
            body.append(".*")
            index += 2
            continue
        }
        when (val char = pattern[index]) {
            '*' -> body.append("[^/]*")
            '?' -> body.append("[^/]")
            else -> {
                if (char in GLOB_LITERAL_ESCAPE) body.append('\\')
                body.append(char)
            }
        }
        index += 1
    }
    body.append('$')
    return Regex(body.toString())
}

private const val GLOB_LITERAL_ESCAPE = "\\.[]{}()+-^$|"
