# WP-13 scenario checklist

Run date: 2026-10-29. Emulator: API 36 AVD `nuum_api36`. Host tests: `./gradlew :app:testDebugUnitTest --tests com.nuum.testing.acceptance.HostAcceptanceTest --tests com.nuum.testing.acceptance.BackupRulesTest` (passed). Instrumented tests were assembled (`:testing:acceptance:assembleDebug`) and not executed. `:app:assembleDebug` passed.

Two host bugs were fixed in `:core:agent` so a real `Kernel` can finish a turn. Both match the Mac host and are called out under the scenarios that need them:

- `turn.context` was ignored, so every turn with a context window waited forever before the first model call. The host now replies with no message replacement. Compaction still happens before the turn; mid-turn compaction is not ported.
- `always` / `never` looked for an `action` field on the tool arguments and for a tool call that is not in memory until after the decision. Write arguments only have `path` and `content`. The host now stores the pending event's action and canonical target, which is what Mac persists.

No feature module was edited to make a check pass.

## 1. Cold start

**Steps.** Install or clear data. Launch `MainActivity`. Look at the sidebar.

**Expected.** No Nunu has status `running`. The sidebar does not show `工作中` / `Working`.

**Automation.** Host test `scenario1_coldStartHasNoRunningNunu` (passed). Instrumented `a_scenario1_coldStartShowsNoRunningNunu` compiled, not run.

**Last result.** Passed on the JVM. A fresh graph lists no agents; a created Nunu is `idle`.

## 2. Create Nunu

**Steps.** Sidebar → 新建 Nunu. Enter a name, pick a color. Shape and material are rolled on that screen. Create. Force-stop the app and open it again. Open the profile.

**Expected.** `profile.json` keeps the name, color, shape, and material.

**Automation.** Host test `scenario2_profileSurvivesReopen` (passed) writes `honey` / `droplet` / `glass` through `AgentPort.create` and reads them back from a new `AppGraph` and from `filesDir/nuum/agents/<id>/profile.json`. The UI roll is not instrumented (emulator blocked).

**Last result.** Passed at the host. Manual UI not run.

## 3. Send with no API key

**Steps.** Open a Nunu. Send `hello` without saving a key.

**Expected.** A readable error (code 2004, text contains `API key`). The transcript file has no key material.

**Automation.** Host test `scenario3_missingKeyIsUnderstandableAndStaysOutOfTheTranscript` (passed). Instrumented `b_scenario3_sendWithoutAKeyShowsTheHostError` compiled, not run.

**Last result.** Passed. `send` throws `NuumException` 2004, message `Missing API key for deepseek`. The planted string `sk-acceptance-not-a-real-key` is not in the exception or in `transcript.jsonl`, and the transcript has no entries.

## 4. Fake model, SendMessage is the body

**Steps.** With the debug router (or the host fake), send a normal line. Watch the transcript.

**Expected.** Streamed plain text is not the visible reply. The visible body is the `SendMessage` content. Tool activity for that call is collapsed, not shown as the reply.

**Automation.** Host test `scenario4_sendMessageIsTheVisibleTranscriptBody` (passed) for the stored transcript. UI not run.

**Last result.** Passed for storage: the only `message` payload is `Visible from SendMessage`. The scratchpad string is not a message payload. The planted key is not in the transcript.

**Defect.** A normal turn appends a `tool` event for `SendMessage` and does not append an `assistant` event (Mac flushes that block; Android only writes one from recovery). `projectAgent` then treats the tool event as an unknown call and `TranscriptPane` draws a single tool as an expanded card. Collapsing starts at two tools, and the unknown-tool path does not drop `SendMessage`. Final UI is likely the message bubble plus an expanded SendMessage card. Not changed. Owners: `:core:agent` (no assistant flush) and `:feature:conversation` (`Projection.kt`).

## 5. Write approval, deny, always, secrets.bin

**Steps.** Fake model calls `write` on `filesDir/nuum/outside-scratch.txt` (under the home root, outside scratch, so the sandbox asks). Deny. Send the same write again. Choose always allow. Send it a third time. Then ask for `noBackupFilesDir/secrets.bin`.

**Expected.** An approval bar appears. Deny comes back to the model as `User denied this tool call.` Always allow is remembered, so the next write of that same path does not ask. `secrets.bin` is still not written.

**Automation.** Host test `scenario5_denyThenAlwaysAndSecretsStaySealed` (passed). Instrumented `c_scenario5_approvalDenyAlwaysAndSealedSecrets` compiled, not run. The instrumented test would save a key through the settings field `api-key-deepseek` and drive the bar (`拒绝` / `Deny`, `始终允许` / `Always allow`).

**Last result.** Passed on the JVM. After deny, a tool message contains `User denied this tool call.` and the note file does not contain `accepted-note`. After always, the file is exactly `accepted-note`. The following write emits no `agent.tool.pending`. The secrets write does not leave `accepted-note` in `secrets.bin`. The model sees `protected`, `outside`, or `Permission denied`. The transcript does not contain the planted key.

## 6. Attachments over the limit

**Steps.** Attach six files, or one file over 10 MB, or a set over 20 MB. Send.

**Expected.** Nothing is sent. The composer keeps the draft. The transcript does not grow.

**Automation.** Host test `scenario6_overLimitAttachmentDoesNotSend` (passed) sends six 1-byte files. The count ceiling is the same gate as the 10 MB and 20 MB ceilings (`attachmentLimitError`). UI picker not run.

**Last result.** Passed. `send` throws code 1007, the message mentions `5`, the transcript is empty, and the fake model is not called.

## 7. Room, upgrade, model CreateTask

**Steps.** Create a local room. Attach a Nunu. Post. Upgrade to NunuBar (`升级为 NunuBar` / `Enable task board`). Post again so the model can call `CreateTask`. Open the task swimlane.

**Expected.** The swimlane shows the card the model created. There is no manual create-task control.

**Automation.** Host test `scenario7_roomUpgradeShowsModelCreateTaskAndNoManualControl` (passed). It also scans `:feature:work` sources for `New task`, `Create task`, `A new task`, `新建任务`, `创建任务`. Instrumented `d_scenario7_roomHasNoManualCreateTaskControl` would open the room UI and assert those strings plus the upgrade control. Not run.

**Last result.** Passed. After a room post, `tasks` is empty (`CreateTask` returns "Enable the task board before creating cards."). After `update(kind = work)` and another post, the only card is `Lane card`. The work sources do not contain a manual create-task label.

**Follow-up (WP-12, not fixed).** `ShellSelection` still does not expose `selectWork`. The sidebar row calls `selectWork`. Creating a NunuBar dismisses the overlay; the new row has to be opened from the sidebar.

## 8. Interrupt a discussion, then continue

**Steps.** In a room with a member, post so a discussion starts. Stop it while the model is in flight. Post again.

**Expected.** The first discussion stops. The Nunu is not left `running`. A later post can still produce a room message.

**Automation.** Host test `scenario8_discussionCanStopAndThenContinue` (passed). The fake model hangs until cancel, then `SendMessage`s `continued after interrupt`. UI buttons `Stop discussion` / `停止` not run.

**Last result.** Passed. After `stopDiscussion` the agent is idle. The next post appends a chat event whose body is `continued after interrupt`.

## 9. Kill the process and reopen

**Steps.** Finish a turn so a message is on disk. Force-stop the process. Launch again.

**Expected.** Status is not `running`. The finished message is still there.

**Automation.** Host test `scenario9_reopenIsNotRunningAndKeepsTheMessage` (passed) closes the graph (new scheduler, same files) and opens another. Instrumented `e_scenario9_relaunchKeepsTheMessageAndIsNotRunning` only recreates the activity in-process, and it was not run. `am force-stop` from the instrumentation process kills the test with the app, so process death is the host test.

**Last result.** Passed. The reopened agent is `idle`. The transcript message is `kept`.

## 10. Language, theme, Proactive

**Steps.** Settings → language English, theme Light. Leave settings. Open Proactive.

**Expected.** Language and theme apply on the next frame and survive relaunch. Proactive shows actions not connected (`Not connected` / `尚未接入`). `actionsAvailable` stays false even after enabling proactive.

**Automation.** Host test `scenario10_languageThemeAndProactiveActions` (passed) through `SettingsPort` and `ProactivePort` on a real `AppGraph`. The settings screen itself was not opened (emulator blocked). Feature UI tests already cover the controls with fakes; they are not this run.

**Last result.** Passed. `set(language = en, theme = light)` returns those values, `get` agrees, and a new graph reads them back from disk. `get`, `configure(enabled = true)`, and `check` all report `actionsAvailable = false`. `check` before configure throws `Proactive mode disabled`, which is why the test enables the policy first.

## 11. Backup rules

**Steps.** Read `AndroidManifest.xml`, `data_extraction_rules.xml`, and `backup_rules.xml`. Do not run `adb backup` and do not upload a backup.

**Expected.** `allowBackup` is false. Cloud backup and device transfer exclude `no_backup`, `no_backup/secrets.bin`, and `file/nuum`. The legacy full-backup rules exclude the same paths.

**Automation.** `BackupRulesTest` (passed). Source read only.

**Last result.** Passed.

## 12. Release APK

**Steps.** `./gradlew :testing:acceptance:checkReleaseBudget`.

**Expected.** Release APK under 30 MB (31,457,280 bytes). No `.so` under `lib/`.

**Automation.** The Gradle task. It is not part of CI.

**Last result.** Size passed, native libraries failed. See [logs/release-budget.txt](logs/release-budget.txt).

- Unsigned release APK: **4,159,311 bytes** after R8 minify and resource shrinking.
- The same APK before R8 was **32,300,616 bytes** (over budget).
- `classes*.dex` does not contain `AcceptanceRouterModel` or `nuum.fakeModel`.
- Eight `.so` files remain, from `androidx.graphics:graphics-path` and DataStore's multi-process counter. They were not stripped. minSdk 28 still needs the graphics-path library for `PathIterator` before API 34.

Debug APK from this run: 41,442,288 bytes (under the 45 MB debug budget). It does contain the router, which is what the instrumented tests select.
