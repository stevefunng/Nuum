import Foundation
import NuumContracts
import Testing
@testable import NuumFeatureSettings

@Test func switchingProviderUsesDefaultModelID() async {
    let (model, port, _, _) = await makeSettings()
    await model.selectProvider(.openai)
    #expect(port.current.defaultModel.provider == .openai)
    #expect(port.current.defaultModel.model == defaultModelID(for: .openai))
    await model.selectProvider(.anthropic)
    #expect(port.current.defaultModel.model == defaultModelID(for: .anthropic))
    await model.selectProvider(.deepseek)
    #expect(port.current.defaultModel.model == defaultModelID(for: .deepseek))
    #expect(await model.snapshot().modelId == DeepSeekModelID.chat)
    #expect(port.patches.allSatisfy { $0.defaultToolPermission == nil })
}

@Test func deepSeekModelChoiceDoesNotResetToTheDefault() async {
    let (model, port, _, _) = await makeSettings(
        sampleSettings(model: ModelRef(provider: .deepseek, model: DeepSeekModelID.chat))
    )
    await model.selectDeepSeekModel(DeepSeekModelID.reasoner)
    #expect(port.current.defaultModel == ModelRef(provider: .deepseek, model: DeepSeekModelID.reasoner))
    #expect(await model.snapshot().modelId == DeepSeekModelID.reasoner)
}

@Test func deepSeekChoiceIsIgnoredForAnotherProvider() async {
    let (model, port, _, _) = await makeSettings(
        sampleSettings(model: ModelRef(provider: .openai, model: defaultModelID(for: .openai)))
    )
    await model.selectDeepSeekModel(DeepSeekModelID.reasoner)
    #expect(port.patches.isEmpty)
    #expect(port.current.defaultModel.provider == .openai)
}

@Test func standingToolPermissionIsNotPatched() async {
    let (model, port, _, _) = await makeSettings(sampleSettings(permission: .always))
    await model.selectTheme(.light)
    await model.selectLanguage(.zhCN)
    await model.selectProvider(.openai)
    #expect(port.current.defaultToolPermission == .always)
    #expect(port.patches.allSatisfy { $0.defaultToolPermission == nil })
    let state = await model.snapshot()
    #expect(state.theme == .light)
    #expect(state.language == .zhCN)
    #expect(SettingsCopy.text(state.language ?? .en, "General") == "通用")
}

@Test func languageFailureUsesTheFixedFlagAndThemeFailureKeepsTheMessage() async {
    let (model, port, _, _) = await makeSettings()
    port.failLanguage = true
    port.themeFailure = "theme disk full"
    await model.selectLanguage(.zhCN)
    let afterLanguage = await model.snapshot()
    #expect(afterLanguage.languageFailed)
    #expect(afterLanguage.language == .en)
    #expect(presentSettings(afterLanguage).languageAlertKey == "Could not change language. Please try again.")
    await model.selectTheme(.light)
    let afterTheme = await model.snapshot()
    #expect(afterTheme.themeError == "theme disk full")
    #expect(port.current.theme == .dark)
    #expect(afterTheme.theme == .dark)
}

@Test func providerFailureStaysOnTheRowAndDoesNotChangeTheModel() async {
    let (model, port, _, _) = await makeSettings()
    port.modelFailure = "model disk full"
    await model.selectProvider(.openai)
    let state = await model.snapshot()
    #expect(state.providerError == "model disk full")
    #expect(state.provider == .deepseek)
    #expect(port.current.defaultModel.model == DeepSeekModelID.reasoner)
    #expect(state.deepSeekModelError == nil)
}

@Test func languageControlStaysBusyWhileTheSaveIsHeld() async {
    let (model, port, _, _) = await makeSettings()
    port.holdLanguage = true
    let task = Task { await model.selectLanguage(.zhCN) }
    for await _ in port.languageHold.entered { break }
    let state = await model.snapshot()
    #expect(state.languageBusy)
    #expect(state.language == .en)
    #expect(!presentSettings(state).languageEnabled)
    port.languageHold.release()
    await task.value
    let done = await model.snapshot()
    #expect(done.language == .zhCN)
    #expect(!done.languageBusy)
    #expect(!done.languageFailed)
}

@Test func emptyStringDeletesAndATypedKeyIsNotStoredOnTheModel() async {
    let (model, _, writer, store) = await makeSettings()
    let secret = "sk-test-deepseek"
    await model.commitAPIKey(provider: .deepseek, value: secret)
    #expect(store.readCount == 0)
    #expect(writer.writes.count == 1)
    #expect(writer.writes[0].0 == .deepseek)
    #expect(writer.writes[0].1 == secret)
    #expect(store.peek().deepseekApiKey == secret)
    let saved = await model.snapshot()
    #expect(!containedStrings(saved).contains(where: { $0.contains(secret) }))
    await model.commitAPIKey(provider: .deepseek, value: "")
    #expect(writer.writes.last?.0 == .deepseek)
    #expect(writer.writes.last?.1 == "")
    #expect(store.peek().deepseekApiKey == nil)
    #expect(store.readCount == 0)
}

@Test func keyStoreFailureKeepsTheMessageWithoutTheKey() async {
    let (model, _, writer, store) = await makeSettings()
    let secret = "sk-test-deepseek"
    writer.failure = NuumError(code: DesktopErrorCode.secretStore, message: "keystore rejected \(secret)")
    await model.commitAPIKey(provider: .deepseek, value: secret)
    let message = await model.snapshot().keyErrors[.deepseek]
    #expect(message == "keystore rejected …")
    #expect(message?.contains(secret) == false)
    #expect(store.peek().deepseekApiKey == nil)
    #expect(store.readCount == 0)
}

@Test func secretStore3001MessageIsShownWithoutTheKey() async {
    let (model, _, writer, _) = await makeSettings()
    writer.failure = NuumError.secretWriteFailed
    await model.commitAPIKey(provider: .openai, value: "sk-test-openai")
    #expect(await model.snapshot().keyErrors[.openai] == SecretStoreMessage.writeFailed)
    #expect(await model.snapshot().keyErrors[.openai]?.contains("sk-test-openai") == false)
}

@Test func openingDoesNotWriteOrReadAKey() async {
    let store = MemorySecretStore()
    store.write(Secrets(deepseekApiKey: "sk-stored-not-in-ui"))
    let writer = RecordingSecretWriter(store: store)
    let model = SettingsModel(settings: FakeSettingsPort(), secrets: writer)
    await model.refresh()
    #expect(writer.writes.isEmpty)
    #expect(store.readCount == 0)
    #expect(store.peek().deepseekApiKey == "sk-stored-not-in-ui")
    let presented = presentSettings(await model.snapshot())
    #expect(presented.keyNotice == .fieldsStartEmpty)
    #expect(presented.missingKeyNotice == .missingKeyNotShown)
    #expect(!presented.showsNoAPIKeyBanner)
    #expect(!containedStrings(await model.snapshot()).joined().contains("sk-stored-not-in-ui"))
}

@Test func selectorsStayDisabledUntilSettingsLoad() async {
    let port = FakeSettingsPort()
    let gate = HoldGate()
    port.getGate = gate
    let model = SettingsModel(settings: port, secrets: RecordingSecretWriter(store: MemorySecretStore()))
    let task = Task { await model.refresh() }
    for await _ in gate.entered { break }
    let loading = presentSettings(await model.snapshot())
    #expect(loading.phase == .loading)
    #expect(loading.navigationEnabled)
    #expect(!loading.languageEnabled)
    #expect(!loading.themeEnabled)
    #expect(!loading.providerEnabled)
    #expect(loading.providerValue == nil)
    #expect(!loading.showDeepSeekModel)
    #expect(loading.keyNotice == .fieldsStartEmpty)
    #expect(!loading.showsNoAPIKeyBanner)
    gate.release()
    await task.value
    let ready = presentSettings(await model.snapshot())
    #expect(ready.phase == .ready)
    #expect(ready.providerValue == "DeepSeek")
    #expect(ready.providerEnabled)
}

@Test func loadFailureDisablesSelectorsAndShowsTheMessage() async {
    let model = SettingsModel(
        settings: FailingSettingsPort(),
        secrets: RecordingSecretWriter(store: MemorySecretStore())
    )
    await model.refresh()
    let presented = presentSettings(await model.snapshot())
    #expect(presented.phase == .loadFailed)
    #expect(presented.loadError == "settings unavailable")
    #expect(presented.providerValue == nil)
    #expect(!presented.providerEnabled)
    #expect(presented.navigationEnabled)
}

@Test func settingsEventUpdatesTheVisiblePreference() async {
    let (model, port, _, _) = await makeSettings()
    var next = port.current
    next.language = .zhCN
    next.theme = .light
    await model.accept(.settingsUpdated(next))
    let state = await model.snapshot()
    #expect(state.language == .zhCN)
    #expect(state.theme == .light)
}

@Test func sameLanguageDoesNotWrite() async {
    let (model, port, _, _) = await makeSettings(sampleSettings(language: .en))
    await model.selectLanguage(.en)
    #expect(port.patches.isEmpty)
}

private final class FailingSettingsPort: SettingsPort, @unchecked Sendable {
    let events: AsyncStream<HostEvent> = AsyncStream { _ in }
    func get() async throws -> PublicSettings {
        throw NuumError(code: 1, message: "settings unavailable")
    }

    func set(_ patch: SettingsPatch) async throws -> PublicSettings {
        throw NuumError(code: 1, message: "settings unavailable")
    }
}
