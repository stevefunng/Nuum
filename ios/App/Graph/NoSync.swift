import NuumContracts

/// Sync seam. Methods do nothing. A later unit is an agent directory and a work timeline.
struct NoSync: SyncPort {
    func pushAgent(agentId: String) async throws {}

    func pullAgent(agentId: String) async throws {}

    func pushWork(workId: String) async throws {}

    func pullWork(workId: String) async throws {}
}
