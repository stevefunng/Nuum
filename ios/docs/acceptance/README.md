# iOS acceptance

WP-13 checklist for the iOS client. Scenario steps and the current result of each one are in [SCENARIOS.md](SCENARIOS.md).

The checklist was written against `main` at `061033920588ca502d5874e3451f2e9c5878cc54` (WP-12). Every scenario is **Not executed on a Mac**. This tree was prepared on Linux. Linux `swift test` does not complete WP-13. The package tests did pass on Swift 6.2.1; that compiler is not Xcode 27.2.

## What a Mac runs

Use Xcode 27.2 (build `27B52`, Swift 6.4.2). Not Xcode 27.3 beta. The app is `com.nuum`, deployment iOS 26.0. Use an iPhone simulator so the width is compact and the Nunu list is its own column.

```sh
cd ios
xcodebuild -project Nuum.xcodeproj -scheme Nuum \
  -destination 'platform=iOS Simulator,name=<iPhone from simctl>' \
  -configuration Debug \
  build
```

`xcrun simctl list devices available` names the runtime that ships with that Xcode. Install the built `Nuum.app`, then launch it.

Debug builds select `AcceptanceRouterModel` only when a launch argument or environment variable asks for it. There is no settings switch. Release builds compile that type out (`#if DEBUG`). A normal debug launch uses `URLSessionModelPort`.

```sh
xcrun simctl launch <UDID> com.nuum -- nuum.fakeModel=router
```

The same switch is `NUUM_FAKE_MODEL=router` (`SIMCTL_CHILD_NUUM_FAKE_MODEL=router` through `simctl`). The router never reads an API key and never logs the request. The host still returns 2004 until a key is stored, so model scenarios save the fake key first.

| User text contains | Router does |
| --- | --- |
| `acceptance-write` | `write` `Application Support/nuum/outside-scratch.txt` with `accepted-note` |
| `acceptance-secrets` | `write` `Application Support/nuum/secrets.json` with `accepted-note` |
| tools include `CreateTask` | `CreateTask` titled `Lane card` |
| anything else | scratchpad text `scratchpad-not-the-body` plus one `SendMessage` (`Visible from SendMessage`) |

The planted key is `sk-acceptance-not-a-real-key`. It is not a provider credential. Do not print it, do not dump the Keychain item, and do not write a secrets file. If a container search hits that string, record the path only.

The router returns immediately. It does not hang, so scenario 8 cannot pause inside a model call the way the Android host fake can. Say so in the log if Stop never appears during the flight.

## Container

Data root: `Library/Application Support/nuum/` inside the simulator data container (`xcrun simctl get_app_container <UDID> com.nuum data`). Documents is unused. Keys are a Keychain generic password, service `nuum.secrets`, account `api-keys`. They are not a file.

Search the container with a count or a path list. Do not `cat` a file that might hold the planted string.

## Host checks that do not need a simulator

From `ios/Packages/NuumAcceptance`:

```sh
swift test
```

Those tests read source. They check the checklist still says every scenario is not executed, that the debug router and the fixtures name the same phrases, that backup-related plist and Keychain attributes are present, and that the known leftovers below are still true. They do not boot Simulator, sign the app, or touch Keychain.

The Xcode app target does not link `NuumAcceptance`. The dependency-direction test forbids that link. Do not add it from this package.

## Known leftovers

Recorded in the checklist. They are not fixed here.

- `NuumSecurity/Package.swift` has no test target, so `NuumSecurityTests` is not part of `swift test`. The Keychain files on disk have not been run on a Mac.
- `AgentToolPendingEvent` has no `workId`.
- `CompactTranscript` has no `activeRequest` or `roomInputs`. The protocol type has both, and the host bridge drops them.
- `ToolTranscript` has no `executionId`. The protocol type has it, and the host bridge drops it.
- `ExecutionPreferences` has no `externalGrants`. The protocol type has it.
- `ShellSelection` has no compact list-return callback. The shell top bar still calls `session.back()` and returns to the list.
