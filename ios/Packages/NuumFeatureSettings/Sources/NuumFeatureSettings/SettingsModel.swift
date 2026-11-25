import Foundation
import NuumContracts

/// Non-secret settings edits. Key characters never enter this state.
struct SettingsUiState: Equatable, Sendable {
    var loaded = false
    var loadError: String?
    var language: Language?
    var theme: ThemePreference?
    var provider: ProviderId?
    var modelId: String?
    var languageBusy = false
    var languageFailed = false
    var themeError: String?
    var providerError: String?
    var deepSeekModelError: String?
    var keyErrors: [ProviderId: String] = [:]
}

/// Edits `SettingsPort` and writes keys through `SecretWriter`.
/// An empty string deletes that provider's key. Nothing here reads a key back.
actor SettingsModel {
    private(set) var state: SettingsUiState
    nonisolated let updates: AsyncStream<SettingsUiState>
    private let updateContinuation: AsyncStream<SettingsUiState>.Continuation
    private let settings: any SettingsPort
    private let secrets: any SecretWriter
    private let events: AsyncStream<HostEvent>

    init(settings: any SettingsPort, secrets: any SecretWriter) {
        self.settings = settings
        self.secrets = secrets
        self.events = settings.events
        let initial = SettingsUiState()
        self.state = initial
        let pair = AsyncStream<SettingsUiState>.makeStream(bufferingPolicy: .bufferingNewest(32))
        self.updates = pair.stream
        self.updateContinuation = pair.continuation
        pair.continuation.yield(initial)
    }

    func snapshot() -> SettingsUiState { state }

    /// Loads settings, then applies later `settings.updated` events.
    func run() async {
        await refresh()
        for await event in events {
            accept(event)
        }
    }

    func refresh() async {
        do {
            apply(try await settings.get())
        } catch is CancellationError {
            return
        } catch {
            mutate {
                $0.loaded = false
                $0.loadError = userFacingMessage(error)
            }
        }
    }

    func accept(_ event: HostEvent) {
        guard case .settingsUpdated(let settings) = event else { return }
        apply(settings)
    }

    func selectLanguage(_ language: Language) async {
        guard state.loaded, !state.languageBusy, state.language != language else { return }
        mutate {
            $0.languageBusy = true
            $0.languageFailed = false
        }
        do {
            let next = try await settings.set(SettingsPatch(language: language))
            mutate {
                adopt(next, into: &$0)
                $0.languageBusy = false
                $0.languageFailed = false
            }
        } catch is CancellationError {
            mutate { $0.languageBusy = false }
        } catch {
            mutate {
                $0.languageBusy = false
                $0.languageFailed = true
            }
        }
    }

    func selectTheme(_ theme: ThemePreference) async {
        guard state.loaded, state.theme != theme else { return }
        do {
            let next = try await settings.set(SettingsPatch(theme: theme))
            mutate {
                adopt(next, into: &$0)
                $0.themeError = nil
            }
        } catch is CancellationError {
            return
        } catch {
            mutate { $0.themeError = userFacingMessage(error) }
        }
    }

    /// Switching provider installs that provider's `DEFAULT_MODEL_ID`.
    func selectProvider(_ provider: ProviderId) async {
        guard state.loaded, state.provider != provider else { return }
        await saveModel(modelRefForProvider(provider), deepSeekRow: false)
    }

    func selectDeepSeekModel(_ modelID: String) async {
        guard state.loaded, state.provider == .deepseek, state.modelId != modelID else { return }
        guard modelID == DeepSeekModelID.chat || modelID == DeepSeekModelID.reasoner else { return }
        await saveModel(ModelRef(provider: .deepseek, model: modelID), deepSeekRow: true)
    }

    /// Blur of a key field. Empty string deletes. The typed value is not stored here.
    func commitAPIKey(provider: ProviderId, value: String) async {
        let submitted = value.isEmpty ? "" : value
        do {
            try await secrets.write(provider: provider, apiKey: submitted)
            mutate { $0.keyErrors[provider] = nil }
        } catch is CancellationError {
            return
        } catch {
            let message = userFacingMessage(error, redacting: submitted)
            mutate { $0.keyErrors[provider] = message }
        }
    }

    private func saveModel(_ model: ModelRef, deepSeekRow: Bool) async {
        do {
            let next = try await settings.set(SettingsPatch(defaultModel: model))
            mutate {
                adopt(next, into: &$0)
                if deepSeekRow {
                    $0.deepSeekModelError = nil
                } else {
                    $0.providerError = nil
                }
            }
        } catch is CancellationError {
            return
        } catch {
            let message = userFacingMessage(error)
            mutate {
                if deepSeekRow {
                    $0.deepSeekModelError = message
                } else {
                    $0.providerError = message
                }
            }
        }
    }

    private func apply(_ settings: PublicSettings) {
        mutate { adopt(settings, into: &$0) }
    }

    private func adopt(_ settings: PublicSettings, into state: inout SettingsUiState) {
        state.loaded = true
        state.loadError = nil
        state.language = settings.language
        state.theme = settings.theme
        state.provider = settings.defaultModel.provider
        state.modelId = settings.defaultModel.model
    }

    private func mutate(_ body: (inout SettingsUiState) -> Void) {
        body(&state)
        updateContinuation.yield(state)
    }
}
