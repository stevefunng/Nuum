# Nuum iOS

iOS 客户端脚手架（WP-00）。工程、包和配置都在 `ios/` 里，不进 pnpm workspace，也不和 Android 或 Mac 桌面共用 Gradle、模块或密钥文件。规格见 [docs/IOS_ARCHITECTURE.md](docs/IOS_ARCHITECTURE.md)。

在 Mac 上用 Xcode 27.2（build `27B52`，Swift 6.4.2）。不用 Xcode 27.3 beta。最低系统 iOS 26.0。Bundle id 是 `com.nuum`。签名团队在这台 Mac 上选，仓库里不提交 team id。

```bash
cd ios
xcodebuild -project Nuum.xcodeproj -scheme Nuum -destination 'generic/platform=iOS Simulator' build

cd Packages/NuumContracts
swift test
```

`swift test` 跑契约和依赖方向，不启动模拟器。模拟器里画出应用名、签名、Keychain 往返要等装了 Xcode 27.2 的 Mac。

密钥只进 Keychain：service `nuum.secrets`，account `api-keys`，`AfterFirstUnlockThisDeviceOnly`，不同步。读取或写入失败抛 `3001`，句子用架构文档里的两句固定英文。Application Support 里不放密钥文件。

入口画面是 `App/RootView.swift`。文件头写着 WP-12 之后才能改。
