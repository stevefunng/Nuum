# Nuum Android

Android PoC. It is not part of the pnpm workspace. Specs: [docs/ANDROID_ARCHITECTURE.md](docs/ANDROID_ARCHITECTURE.md).

Requirements: JDK 21 and Android SDK platform `platforms;android-37.0`.

```bash
./gradlew :app:assembleDebug test
```

`test` runs JVM unit tests and `checkDependencyDirection`. CI gate is `./gradlew test assembleDebug` and does not boot an emulator. `compileSdk` is 37, `targetSdk` is 36, `minSdk` is 28.

Emulator smoke on this Cloud VM was skipped: a software-rendered API 36 cold boot did not reach `sys.boot_completed`. Do not treat that as a CI failure.
