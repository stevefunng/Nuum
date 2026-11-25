# WP-13 scenario checklist

Written 2026-11-25 against `061033920588ca502d5874e3451f2e9c5878cc54` (WP-12 on `main`). Machine: Linux, no Xcode, no iOS Simulator, no Keychain. Xcode 27.2 was not run. Xcode 27.3 beta was not used.

`swift test` in `ios/Packages/NuumAcceptance` passed on Swift 6.2.1 (the Linux toolchain, not the Xcode 27.2 Swift 6.4.2). That run reads source. It does not complete WP-13.

**Simulator.** Not executed on a Mac. That sentence in each scenario is the result. A later Mac follows [README.md](README.md), fills the log, and changes the sentence only for a scenario it actually ran.

Android scenarios 1–12 are the script. iOS substitutions:

- Keychain item `nuum.secrets` / `api-keys`, not `secrets.bin` and not `noBackupFilesDir`.
- SwiftUI document picker (`fileImporter`), not Storage Access Framework.
- No `adb backup`, no backup upload, and no iCloud copy. Do not run a device backup.

The planted string is `sk-acceptance-not-a-real-key`. Do not print it. Do not write a secrets file. A container search reports a path or a count, never the matching line.

`turn.context` is answered with no message replacement. Mid-turn compaction is not ported. That matches the Android acceptance record and is not one of the twelve failures.

## 1. Cold start

**Steps.** Delete the app or erase the simulator. Launch `com.nuum` with no fake-model argument. On an iPhone simulator the first screen is the Nunu list. Default copy is Chinese.

**Expected.** No row shows `工作中` or `Working`. The empty list can show `还没有 Nunu`. Nothing is `running`.

**Simulator.** Not executed on a Mac.

## 2. Create a Nunu

**Steps.** Open the new menu (`新建`, hint `新建 Nunu`). Choose `创建新 Nunu`. Enter a name in `nunu-name`. Pick a color, for example Honey (`swatch-honey`). Shape and material are rolled on that screen; the user does not pick them. Tap `创建`. The shell top bar's back control (the upper one, accessibility label `Nunu`) calls `session.back()` and returns to the list. Terminate the process (`xcrun simctl terminate`) and launch again. Open the profile.

**Expected.** `Library/Application Support/nuum/agents/<id>/profile.json` still has the same name, `avatarColor`, `avatarShape`, and `avatarMaterial` that were written at create time. Record those four values before terminate and compare them after. Do not require a particular roll such as `droplet` / `glass`.

**Simulator.** Not executed on a Mac.

## 3. Send with no API key

**Steps.** Fresh install, or a Nunu whose Keychain item is absent. Do not save a key. Open the Nunu and send `hello`. The production model port is fine here: the host rejects the turn before any request.

**Expected.** A readable error whose text contains `API key`. With an empty secret store the sentence is `Missing API key for deepseek` (code 2004). The conversation surface shows that sentence and does not need to show the digits. `transcript.jsonl` is missing or has no entries, and it does not contain the planted string. The container has no plaintext secret file.

**Simulator.** Not executed on a Mac.

## 4. SendMessage is the visible body

**Steps.** Save the planted key in Settings (`api-key-deepseek`, submit, then `close-settings`). Relaunch with `nuum.fakeModel=router`. Open a Nunu and send an ordinary line that is not `acceptance-write` or `acceptance-secrets`.

**Expected.** The stored message body is `Visible from SendMessage`. The scratchpad string `scratchpad-not-the-body` is not a message payload. The transcript does not contain the planted string.

**Source observation, not a simulator result.** `HostTurns.finishRun` drops `liveParts` and does not append an assistant event. `handleDelegate` does append a `tool` event for `SendMessage`. `projectAgent` draws an unknown tool event as a tool card. `SendMessage` is omitted only when it is already an assistant part. The visible screen is likely the message bubble plus an expanded SendMessage card. Confirm or clear this on the simulator. Not changed. Owners: `NuumAgent` (no assistant flush) and `NuumFeatureConversation` (`Projection.swift`).

**Simulator.** Not executed on a Mac.

## 5. Write approval and Keychain

**Steps.** With the planted key saved and the debug router on, send `acceptance-write the note`. An approval bar offers `拒绝` / `Deny`, allow once, and `始终允许` / `Always allow`. Deny. Send `acceptance-write the note again`. Choose always allow. Send `acceptance-write the note once more`. Then send `acceptance-secrets now`.

**Expected.** Deny comes back to the model as `User denied this tool call.` and `Application Support/nuum/outside-scratch.txt` does not contain `accepted-note`. After always allow, that file is exactly `accepted-note`. The third write of the same path does not ask. The secrets write does not create `accepted-note` in `secrets.json` or in any other file. The model text contains `protected`, `outside`, or `Permission denied` (the sealed path uses `Path is inside a protected host-only store.`).

Then confirm the container. Search the data container, including `Library/Application Support`, Documents, and preferences, for the planted string and for the four sealed names (`secrets.bin`, `secrets.json`, `host-secrets.json`, `credentials.json`). No file contains the planted string. `secrets.bin` is not a store on iOS. Keychain holds the JSON. Do not dump the item. A later send that gets past 2004 is enough evidence the key was stored.

**Simulator.** Not executed on a Mac.

## 6. Attachments over the limit

**Steps.** With the planted key saved, attach files through the document picker: composer plus (`输入框操作`), then `添加附件`. `IOSDesktopPort` presents `fileImporter` with multiple selection. Prepare the files outside this repo. Do not commit them. Try one of: six files, one file over 10 MB, or a set over 20 MB. Send.

**Expected.** Nothing is sent. The composer keeps the draft. The transcript does not grow. The count ceiling is code 1007 and the message mentions `5` (`At most 5 attachments per message.`). The 10 MB and 20 MB ceilings are the same gate. This is not a Storage Access Framework flow.

The key check runs before the attachment check, so this scenario needs the fake key. Otherwise the error is 2004 and the ceiling is not what was tested.

**Simulator.** Not executed on a Mac.

## 7. Room, upgrade, and CreateTask

**Steps.** With the planted key and the debug router, open `新建` and choose `创建 NunuBar` (`Create NunuBar`). The create screen's local-room control is `本地群聊`. Enter a name in `work-create-name`. Create. `onCreated` only calls `dismissOverlay`, and `ShellSelection` has no `selectWork`, so the new row is opened from the sidebar. Attach a Nunu. Post. Upgrade with `升级为 NunuBar` (`Enable task board`). Post again so the model can call `CreateTask`. Open the task swimlane.

**Expected.** The swimlane shows `Lane card`. There is no manual create-task control (`New task`, `Create task`, `A new task`, `新建任务`, `创建任务`). Before the upgrade, a room post does not leave that card. The work sources under `NuumFeatureWork/Sources` do not contain those labels; the package test reads them.

**Follow-up, not a failed create.** After create, dismiss the overlay and open the row from the list. The shell top bar still returns to the list. The content chevron is wired to `dismissOverlay` and is not that return. See known leftovers.

**Simulator.** Not executed on a Mac.

## 8. Interrupt a discussion, then continue

**Steps.** In a room with a member, post so a discussion starts. Stop it while the model is in flight (`停止讨论` / `Stop discussion`). Post again.

**Expected.** The first discussion stops. The Nunu is not left `工作中` / `Working`. A later post can still produce a room message.

**Procedure limit.** `AcceptanceRouterModel` returns on the first call. It does not wait for cancel. If the stop control never appears during the flight, write that in the log. That is the router, not by itself a stuck `running` agent. A hang-until-cancel model would have to be injected in the composition root, which this package does not edit. If the agent stays `Working` after the room goes idle, that is a defect for `NuumAgent`.

**Simulator.** Not executed on a Mac.

## 9. Kill the process and reopen

**Steps.** With the planted key and the debug router, finish a turn so `Visible from SendMessage` is on disk. Terminate the process. Launch again with the same argument.

**Expected.** The list does not show `工作中` / `Working`. The finished message is still in the transcript. The planted string is not in the transcript. Process death is `simctl terminate`, then a new launch. Leaving the conversation with the shell top bar is not process death.

**Simulator.** Not executed on a Mac.

## 10. Language, theme, and Proactive

**Steps.** Settings (`设置`). Language English (`option-en`). Theme Light (`theme-select`, `option-light`). Leave settings. Open Proactive (`open-proactive`). Turn the proactive switch on. Leave the app and launch it again.

**Expected.** Language and theme apply on the next frame and survive relaunch. English copy and the light palette are visible after relaunch without opening Settings first. Proactive shows actions disconnected: identifier `agent-actions-status` reads `Not connected` / `尚未接入`. `actionsAvailable` stays false after the switch is on. Context sources can also read `Not connected`. The screen does not offer a menu-bar extra or a push toggle.

**Simulator.** Not executed on a Mac.

## 11. Backup exclusion

**Steps.** Read `ios/App/Info.plist`, `ios/App/Nuum.entitlements`, `ios/App/PrivacyInfo.xcprivacy`, the Keychain attributes in `NuumSecurity`, and `DataDirectoryProtection` in `NuumStorage`. Do not run a backup. Do not use iCloud. Do not print a key. There is no `adb backup` step.

**Expected.** Info.plist does not declare `UIBackgroundModes`, `UIFileSharingEnabled`, `LSSupportsOpeningDocumentsInPlace`, or `NSAllowsArbitraryLoads`. Entitlements stay an empty dictionary (no iCloud, App Group, or push). Privacy tracking is false. The data root is marked `isExcludedFromBackup`. The Keychain item is `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` and not synchronizable. A backup or a new device must not receive the key. The package test reads those sources. It does not perform a backup, and it does not complete this scenario.

**Simulator.** Not executed on a Mac.

## 12. Release build

**Steps.** On a Mac, with Xcode 27.2, build the `Nuum` scheme in the Release configuration for the simulator or a generic iOS destination. Record the `.app` size. Search the Release binary for `AcceptanceRouterModel`. List embedded frameworks. Do not add a 30 MB gate: the iOS architecture does not set one. The Android APK budget stays on Android.

**Expected.** The Release product does not contain `AcceptanceRouterModel` (the type is inside `#if DEBUG`, and the Release configurations do not set `SWIFT_ACTIVE_COMPILATION_CONDITIONS`). Debug may contain it. No Datadog, Sentry, Firebase, Alamofire, or other remote Swift package is linked. Record size and the framework list in `logs/` when a Mac actually builds. A size number without that build is not a result.

**Simulator.** Not executed on a Mac.

## Known leftovers

These are true in the WP-12 tree. They do not by themselves fail scenarios 1–12. Fixes belong to the module that owns the file. This package does not edit them.

- WP-02 Keychain has not been verified on a Mac. `ios/Packages/NuumSecurity/Tests/NuumSecurityTests/` has `KeychainSecretStoreTests.swift` and `SecretsCodecTests.swift`, and `NuumSecurity/Package.swift` declares no test target. `NuumSecurityTests` is not part of `swift test`. A Linux stand-in for Keychain would not count.
- `AgentToolPendingEvent` has no `workId`. Android's pending event does not have that field either. The iOS architecture says a pending event that carries `workId` should not draw the one-to-one approval bar. The contract type cannot say so. Owner: `NuumContracts`.
- `CompactTranscript` lacks `activeRequest` and `roomInputs`. `NuumProtocol` has both. `Bridge.swift` drops them, and `HostTurns` writes `activeRequest: nil`, `roomInputs: nil`. Owner: `NuumContracts` for the type, `NuumAgent` for the values it stores.
- `ToolTranscript` lacks `executionId`. `NuumProtocol` has it. `Bridge.swift` drops it, and the delegate path stores `executionId: nil`. `ToolCallPart` on the contract side does have `executionId`. Owner: `NuumContracts` and `NuumAgent`.
- `ExecutionPreferences` lacks `externalGrants`. `NuumProtocol` has the field. The profile form hides the local-computer fold until the contract grows it. Owner: `NuumContracts`. Not a settings-scenario failure.
- `ShellSelection` has no compact list-return callback (`selectWork`, `onBack`, or a return-to-list closure). The shell top bar still calls `session.back()` and returns to the list. `RootView` wires the conversation and work chevrons, and room creation, to `dismissOverlay`. Creating a room does not select it. Owner: `NuumFeatureShell` for the selection type, `App/RootView.swift` for the wiring. WP-13 does not edit either.

`NuumContracts` `dependencyDirectionHolds` already fails on this baseline, before any WP-13 file. The scan flags the word Network in host prompt copy and shell copy, UIKit in `App`, and it still expects `RootView.swift` to begin with the scaffold comment and to show `Text("Nuum")`. WP-12 replaced that placeholder. Not a scenario failure, and not edited here.
