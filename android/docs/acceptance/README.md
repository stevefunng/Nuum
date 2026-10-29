# Android acceptance

WP-13 checklist and tests for the PoC. Scenario results are in [SCENARIOS.md](SCENARIOS.md). Logs from this run are in [logs/](logs/).

The acceptance module (`:testing:acceptance`) is an instrumented test APK aimed at `:app`. It is not part of the CI `test` task. Host-driven checks live in `android/testing/acceptance/src/host/kotlin` and are compiled into `:app`'s unit tests, so `./gradlew test` runs them on the JVM.

## Host tests (no emulator)

From `android/`:

```sh
./gradlew :app:testDebugUnitTest \
  --tests com.nuum.testing.acceptance.HostAcceptanceTest \
  --tests com.nuum.testing.acceptance.BackupRulesTest
```

These build an `AppGraph` with a fake `ModelPort` and an in-memory `SecretStore`. Production `NuumApplication` still calls `AppGraph(context)` and uses `OkHttpModelPort` plus the keystore.

## Instrumented tests

```sh
./gradlew :testing:acceptance:assembleDebug
./gradlew :testing:acceptance:connectedDebugAndroidTest
```

`assembleDebug` builds the test APK. `connectedDebugAndroidTest` needs a booted emulator: `sys.boot_completed=1` and a working `package` service, not merely `adb devices` showing `device`.

The test module passes `-e nuum.fakeModel router`. On a **debug** build that selects `AcceptanceRouterModel` inside `android/app/src/debug`. There is no settings switch. A normal debug launch without that argument uses `OkHttpModelPort`. The router class is not in the release source set.

User text the router understands:

| Text contains | Model does |
| --- | --- |
| `acceptance-write` | `write` `filesDir/nuum/outside-scratch.txt` |
| `acceptance-secrets` | `write` `noBackupFilesDir/secrets.bin` |
| (tools include `CreateTask`) | `CreateTask` titled `Lane card` |
| anything else | scratchpad text plus one `SendMessage` (`Visible from SendMessage`) |

## Install a debug APK for the manual steps

```sh
sudo chmod 666 /dev/kvm   # this VM only; it does not persist
./gradlew :app:assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell am start -n com.nuum/.MainActivity
```

The debug APK does not enable the fake model. Manual checks that need a model either stop at the missing-key error or require a real key. Do not put a real provider key in a log.

## Release size

```sh
./gradlew :testing:acceptance:checkReleaseBudget
```

This builds the release APK and fails if it is 30 MB or larger, if `lib/` contains a `.so`, or if the debug model router is in the dex. The current result is in [logs/release-budget.txt](logs/release-budget.txt).
