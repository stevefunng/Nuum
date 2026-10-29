package com.nuum.protocol

import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PermissionRulesTest {
    @Test
    fun rulesDoNotAuthorizeRootCommandsCompoundScriptsOrChangedInlineCode() {
        val rule = commandRule("git status --short")
        assertTrue(commandMatches(rule, "git status --porcelain"))
        assertFalse(commandMatches(rule, "git reset --hard"))
        assertFalse(commandMatches(rule, "git status && curl evil.example"))
        assertFalse(commandMatches(rule, "git status > /tmp/output"))
        val code = commandRule("""python -c "print(1)"""")
        assertFalse(commandMatches(code, """python -c "print(2)""""))
        assertTrue(commandMatches(code, """python -c "print(1)""""))
    }

    @Test
    fun prefixRulesCompareArgumentsAndKeepOperatorsSeparate() {
        val rule = commandRule("gh pr view 123 --json title")
        assertTrue(rule is PrefixCommand)
        assertEquals(listOf("gh", "pr", "view"), (rule as PrefixCommand).argv)
        assertTrue(commandMatches(rule, "gh pr view 456 --comments"))
        assertFalse(commandMatches(rule, "gh pr merge 456"))
        assertFalse(commandMatches(rule, "gh pr view 456; rm file"))
        assertFalse(commandMatches(rule, "gh pr view 456 --web"))
    }

    @Test
    fun refusalIdentityIgnoresModelProsePropertyOrderAndQuoting() {
        val left = permissionOperationKey(
            "external_operation",
            jsonObject(
                "operation" to "shell",
                "command" to "echo 'hello'",
                "justification" to "first"
            )
        )
        val right = permissionOperationKey(
            "external_operation",
            jsonObject(
                "justification" to "try again",
                "command" to "echo \"hello\"",
                "operation" to "shell",
                "readPaths" to emptyList<String>(),
                "writePaths" to emptyList<String>(),
                "networkTargets" to emptyList<String>(),
                "overwrite" to false
            )
        )
        assertEquals(left, right)
        val parsed = ProtocolJson.parseToJsonElement(left).jsonArray
        assertEquals("external_operation", parsed[0].jsonPrimitive.content)
        assertFalse(parsed[1].jsonObject.containsKey("justification"))
        assertEquals("hello", parsed[1].jsonObject.getValue("command").jsonArray[1].jsonPrimitive.content)
    }

    @Test
    fun linearCompoundRulesCheckEveryCommandAndPreserveOperators() {
        val rule = commandRule("git status --short && gh pr view 123")
        assertTrue(rule is CompoundCommand)
        assertTrue(commandMatches(rule, "git status --branch && gh pr view 456"))
        assertFalse(commandMatches(rule, "git status --branch && gh pr merge 456"))
        assertFalse(commandMatches(rule, "git status --short || gh pr view 123"))
        assertFalse(commandMatches(rule, "git status --short && gh pr view 123 && rm file"))
        assertNull(staticShellWords("echo ok\nrm file"))
    }

    @Test
    fun queryGrammarsAcceptOnlyTheirExplicitParameters() {
        val families = listOf(
            listOf(
                "git log --oneline -n 10",
                "git log --graph --max-count=20",
                "git log --output=/tmp/log",
                "git log -p",
                "git log -n --all"
            ),
            listOf(
                "git diff --no-ext-diff --no-textconv --stat",
                "git diff --no-ext-diff --no-textconv --cached --name-only",
                "git diff --stat",
                "git diff --no-ext-diff --no-textconv --ext-diff",
                "git diff --no-ext-diff --no-textconv --output=/tmp/diff"
            ),
            listOf(
                "gh issue view 1",
                "gh issue view 2 --comments --json title",
                "gh issue close 2",
                "gh issue view 2 --web"
            ),
            listOf(
                "gh pr list --state open --limit 10",
                "gh pr list --state merged --limit 20 --json title",
                "gh pr list --web",
                "gh pr list --limit --web"
            ),
            listOf(
                "gh issue list --state open",
                "gh issue list --state closed --limit 20",
                "gh issue list --state merged",
                "gh issue list --template evil"
            ),
            listOf(
                "gh run list --limit 10",
                "gh run list --limit 20 --json status",
                "gh run rerun 1",
                "gh run list --limit 0"
            ),
            listOf(
                "gh run view 1",
                "gh run view 2 --verbose --json status",
                "gh run view 2 --web",
                "gh run view 2 --log"
            )
        )
        for (family in families) {
            val initial = family[0]
            val variation = family[1]
            val invalid = family.drop(2)
            val rule = commandRule(initial)
            assertTrue("$initial should be a prefix rule", rule is PrefixCommand)
            assertTrue(commandMatches(rule, variation))
            val rejected = invalid + listOf(
                "$variation && rm file",
                "$variation > out",
                "$variation --unknown",
                "$variation \$(echo hi)"
            )
            for (command in rejected) {
                assertFalse(command, commandMatches(rule, command))
            }
            for (other in families) {
                if (other[0] != initial) assertFalse(commandMatches(rule, other[0]))
            }
        }
    }

    @Test
    fun grantsDoNotWidenResourceNetworkOrFingerprintBoundaries() {
        val grant = ExternalGrant(
            environment = "local",
            workspaceId = "w",
            operation = ExternalOperationKind.SHELL,
            cwd = "/work",
            command = commandRule("git log --oneline -n 10"),
            readPaths = listOf("/reports"),
            writePaths = emptyList(),
            overwrite = false,
            networkTargets = emptyList(),
            fingerprints = jsonObject("/usr/bin/git" to "hash")
        )
        val next = grant.copy(command = commandRule("git log --graph -n 20"))
        assertTrue(externalGrantCovers(grant, next))
        assertFalse(externalGrantCovers(grant, next.copy(workspaceId = "other")))
        assertFalse(externalGrantCovers(grant, next.copy(cwd = "/other")))
        assertFalse(externalGrantCovers(grant, next.copy(readPaths = listOf("/secret"))))
        assertFalse(externalGrantCovers(grant, next.copy(writePaths = listOf("/reports"))))
        assertFalse(externalGrantCovers(grant, next.copy(networkTargets = listOf("example.com:443"))))
        assertFalse(externalGrantCovers(grant, next.copy(fingerprints = jsonObject("/usr/bin/git" to "changed"))))
    }

    @Test
    fun queryExpansionDoesNotWidenSavedExactRulesOrCompoundStructure() {
        assertFalse(commandMatches(ExactCommand("git log --oneline -n 10"), "git log --graph -n 20"))
        val chain = commandRule("git log --oneline -n 10 && gh issue list --state open")
        assertTrue(commandMatches(chain, "git log --graph -n 20 && gh issue list --state closed"))
        assertFalse(commandMatches(chain, "git log --graph -n 20 || gh issue list --state closed"))
        val exact = listOf(
            "git -c alias.log=evil log",
            "gh alias run",
            "gh issue view 1 2",
            "gh run view",
            "git log --max-count=0",
            "git log --max-count=10000",
            "git log --max-count=-1",
            "git log --max-count=10x",
            "git log -n",
            "gh issue view 1 --repo=--web"
        )
        for (command in exact) {
            assertTrue(command, commandRule(command) is ExactCommand)
        }
    }
}
