package com.nuum.agent

/** Room discussion policy. These three numbers live here, not in protocol. */
data class DiscussionLimits(
    val rounds: Int,
    val messages: Int,
    val perTurn: Int
)

val discussionLimits = DiscussionLimits(rounds = 3, messages = 10, perTurn = 2)

const val DEFAULT_MAX_CONCURRENT_RUNS = 3

/** A user wake is 0 hops. An agent wake is parent + 1. */
const val MAX_HOPS = 3

/** Same ordered pair (from, to) per minute. */
const val WAKE_RATE_LIMIT = 3
const val WAKE_RATE_WINDOW_MS = 60_000L

/** One new teammate per turn. Creation is not approval-gated, so the cap is hard. */
const val MAX_CREATES_PER_RUN = 1

const val MAX_AGENTS = 50

const val PROFILE_FACT_LIMIT = 100
const val RECALL_BUDGET = 4_000
const val HALF_LIFE_DAYS = 30.0

/** Unknown models use the same window. Do not guess a provider's real length. */
const val DEFAULT_CONTEXT_WINDOW = 128_000

const val COMPACTION_RATIO = 0.75

const val RUN_WORK_CLI_UNIMPLEMENTED =
    "This version of Nuum has no local executable. RunWorkCLI is not implemented."

const val MAX_AGENTS_MESSAGE =
    "Refused: there are already $MAX_AGENTS agents. Ask the user to delete one first."
