package com.nuum.feature.shell

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTextReplacement
import com.nuum.contracts.AgentCreateParams
import com.nuum.contracts.AgentProfile
import com.nuum.contracts.AgentRuntime
import com.nuum.contracts.AgentSettings
import com.nuum.contracts.AgentStatus
import com.nuum.contracts.AgentView
import com.nuum.contracts.Language
import com.nuum.contracts.ModelRef
import com.nuum.contracts.ProviderId
import com.nuum.contracts.SidebarOrganization
import com.nuum.contracts.SidebarSection
import com.nuum.feature.shell.motion.LocalAvatarRandom
import com.nuum.feature.shell.motion.LocalReducedMotion
import com.nuum.feature.shell.motion.LocalUnboxFrameClock
import com.nuum.feature.shell.motion.UnboxFrameClock
import com.nuum.feature.shell.support.FakeShellPorts
import com.nuum.protocol.AGENT_AVATAR_COLORS
import com.nuum.protocol.SIDEBAR_UNIQUENESS_MESSAGE
import com.nuum.protocol.rollAgentAvatar
import kotlin.random.Random
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], qualifiers = "w411dp-h891dp")
class ShellUiTest {
    @get:Rule
    val rule = createComposeRule()

    @Test
    fun emptySidebarShowsTheEmptyCopy() {
        val fake = FakeShellPorts()
        rule.setContent { NuumShell(fake.ports) {} }
        rule.waitForIdle()
        rule.onNodeWithText("No Nunu yet").assertIsDisplayed()
    }

    @Test
    fun pinMovesTheAgentIntoThePinnedSection() {
        val fake = FakeShellPorts(initialAgents = listOf(agent("a", "Ada")))
        rule.setContent { NuumShell(fake.ports) {} }
        rule.waitForIdle()
        rule.onNodeWithText("Ada").assertIsDisplayed()
        rule.onNodeWithTag("agent-a").performSemanticsAction(SemanticsActions.OnLongClick)
        rule.onNodeWithText("Pin").performClick()
        rule.waitForIdle()
        rule.onNodeWithText("Pinned Nunu").assertIsDisplayed()
        check(fake.settings.sidebar?.pinnedAgentIds == listOf("a")) {
            "pinned ids were ${fake.settings.sidebar?.pinnedAgentIds}"
        }
    }

    @Test
    fun duplicateGroupNameShowsTheProtocolSentence() {
        val fake = FakeShellPorts(
            initialAgents = listOf(agent("a", "Ada")),
            sidebar = SidebarOrganization(
                sections = listOf(
                    SidebarSection("g1", "Design", listOf("a")),
                    SidebarSection("g2", "Research", emptyList())
                )
            )
        )
        rule.setContent { NuumShell(fake.ports) {} }
        rule.waitForIdle()
        rule.onNodeWithContentDescription("Actions for Research").performClick()
        rule.onNodeWithText("Rename group…").performClick()
        rule.onNodeWithTag("group-name-field").performTextReplacement("Design")
        rule.onNodeWithText("Save").performClick()
        rule.waitForIdle()
        rule.onNodeWithText(SIDEBAR_UNIQUENESS_MESSAGE).assertIsDisplayed()
        rule.onNodeWithText("Could not save sidebar changes. Please try again.").assertDoesNotExist()
        check(fake.sidebarSets == 0) { "duplicate name was written ${fake.sidebarSets} times" }
    }

    @Test
    fun createSubmitsTheChosenColorAndOneRolledAppearance() {
        val random = CountingRandom(7)
        val expected = rollAgentAvatar(Random(7))
        val other = AGENT_AVATAR_COLORS.first { it.id != expected.color }
        val fake = FakeShellPorts()
        rule.setContent {
            CompositionLocalProvider(LocalAvatarRandom provides random) {
                NuumShell(fake.ports) {}
            }
        }
        openCreate()
        val bitsAfterOpen = random.bits
        rule.onNodeWithTag("swatch-${other.id}").performClick()
        check(random.bits == bitsAfterOpen) { "color change rerolled the avatar (${random.bits} vs $bitsAfterOpen)" }
        rule.onNodeWithTag("nunu-name").performTextInput("Milo")
        rule.onNodeWithText("Create").performClick()
        rule.waitForIdle()
        val params = fake.created.single()
        check(params == AgentCreateParams(
            name = "Milo",
            description = "",
            avatarColor = other.id,
            avatarShape = expected.shape,
            avatarMaterial = expected.material
        )) { "create params were $params, roll was $expected" }
        check(random.bits == bitsAfterOpen) { "submit rerolled the avatar" }
    }

    @Test
    fun reducedMotionSkipsTheUnboxClock() {
        val clock = RecordingUnboxClock()
        rule.setContent {
            CompositionLocalProvider(
                LocalReducedMotion provides true,
                LocalUnboxFrameClock provides clock
            ) {
                NuumShell(FakeShellPorts().ports) {}
            }
        }
        openCreate()
        rule.mainClock.advanceTimeBy(2_000)
        rule.waitForIdle()
        check(clock.frames == 0) { "unbox clock ran ${clock.frames} frames" }
        rule.onNodeWithTag("unbox-settled").assertExists()
        rule.onNodeWithTag("unbox-packaging").assertDoesNotExist()
    }

    private fun openCreate() {
        rule.waitForIdle()
        rule.onNodeWithContentDescription("New").performClick()
        rule.onNodeWithText("Create new Nunu").performClick()
        rule.waitForIdle()
    }
}

private class CountingRandom(seed: Int) : Random() {
    private val delegate = Random(seed)
    var bits: Int = 0
        private set

    override fun nextBits(bitCount: Int): Int {
        bits += 1
        return delegate.nextBits(bitCount)
    }
}

private class RecordingUnboxClock : UnboxFrameClock {
    var frames: Int = 0

    override suspend fun awaitFrame(onFrame: (frameTimeNanos: Long) -> Unit) {
        frames += 1
        onFrame(frames * 16_000_000L)
    }
}

internal fun agent(id: String, name: String): AgentView = AgentView(
    profile = AgentProfile(
        id = id,
        name = name,
        description = "",
        createdAt = 1_700_000_000_000L
    ),
    settings = AgentSettings(model = ModelRef(ProviderId.DEEPSEEK, "deepseek-chat")),
    runtime = AgentRuntime(
        status = AgentStatus.IDLE,
        unread = false,
        lastActivityAt = 1_700_000_000_000L
    )
)
