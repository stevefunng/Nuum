import Foundation
import NuumAgent
import NuumContracts
import NuumFeatureConversation
import NuumFeatureShell
import NuumFeatureWork
import NuumKernel
import NuumSecurity
import NuumStorage
import NuumTools
import os

enum GraphBootError: Error {
    case applicationSupportUnavailable
}

/// Hand-built composition root. No DI container.
/// `identity` and `sync` are the seams from the architecture; this UI does not call them.
/// No `ProactiveSource` is registered, so proactive actions stay disconnected.
@MainActor
final class AppGraph {
    let picker: DocumentPickerModel
    let clock: any Clock
    let secretWriter: SecretStoreWriter
    let identity: any IdentityContext
    let sync: any SyncPort
    let desktop: IOSDesktopPort
    let settingsPort: any SettingsPort
    let agentPort: any AgentPort
    let workPort: any WorkPort
    let proactivePort: any ProactivePort
    let shellPorts: ShellPorts
    let workPorts: WorkPorts
    let conversationPorts: ConversationPorts

    private let store: FileAgentStore
    private let host: HostRuntime
    private let log = Logger(subsystem: "com.nuum", category: "graph")

    init(
        picker: DocumentPickerModel,
        model modelOverride: (any ModelPort)? = nil,
        secrets secretOverride: (any SecretStore)? = nil
    ) throws {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw GraphBootError.applicationSupportUnavailable
        }
        let nuumURL = support.appendingPathComponent(NuumDataDirectory.name, isDirectory: true)
        let store = try FileAgentStore(root: nuumURL)
        let nuumRoot = normalizePath(store.root.path)
        let dataParent = normalizePath(store.root.deletingLastPathComponent().path)
        // Bookmark bytes sit beside `nuum/` and stay sealed, so a project root cannot uncover them.
        let bookmarkDir = normalizePath(support.appendingPathComponent("nuum-access", isDirectory: true).path)
        var secretPaths = sealedSecretPaths(nuumRoot: nuumRoot, dataParent: dataParent)
        secretPaths.append(bookmarkDir)
        var denied = hostDeniedRoots(nuumRoot: nuumRoot, dataParent: dataParent)
        denied.append(bookmarkDir)
        let secretStore = secretOverride ?? KeychainSecretStore()
        let model = modelOverride ?? DebugModelPorts.select(nuumRoot: nuumRoot)
        let clock = NuumKernel.SystemClock()
        let supervisor = makeInProcessTurnSupervisor()
        let tools = CarvingToolBackend(delegate: LocalToolBackend(), sealed: secretPaths)
        let kernel = Kernel(model: model, tools: tools, supervisor: supervisor, clock: clock)
        let host = HostRuntime(
            store: store,
            kernel: kernel,
            secretStore: secretStore,
            tools: tools,
            clock: clock,
            supervisor: supervisor,
            nuumRoot: nuumRoot,
            osLabel: nuumOSLabel(),
            timeZone: TimeZone.current.identifier,
            deniedRoots: denied
        )
        let settingsPort = host.settingsPort
        let agentPort = host.agentPort
        let workPort = host.workPort
        let proactivePort = host.proactivePort
        let desktop = IOSDesktopPort(picker: picker)
        self.picker = picker
        self.clock = clock
        self.secretWriter = SecretStoreWriter(store: secretStore)
        self.identity = LocalOnly()
        self.sync = NoSync()
        self.desktop = desktop
        self.settingsPort = settingsPort
        self.agentPort = agentPort
        self.workPort = workPort
        self.proactivePort = proactivePort
        self.shellPorts = ShellPorts(agents: agentPort, settings: settingsPort, desktop: desktop, work: workPort)
        self.workPorts = WorkPorts(work: workPort, agent: agentPort, desktop: desktop)
        self.conversationPorts = ConversationPorts(agent: agentPort, desktop: desktop)
        self.store = store
        self.host = host
    }

    /// Opens the file tree and starts the host. Failures are logged without key material or paths.
    func start() async {
        picker.restoreBookmarks()
        do {
            try await store.open()
        } catch {
            log.error("Couldn't open the local store")
        }
        do {
            try await host.start()
        } catch {
            log.error("Couldn't start the host")
        }
    }
}

private func nuumOSLabel() -> String {
    let version = ProcessInfo.processInfo.operatingSystemVersion
    if version.patchVersion == 0 {
        return "iOS \(version.majorVersion).\(version.minorVersion)"
    }
    return "iOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
}
