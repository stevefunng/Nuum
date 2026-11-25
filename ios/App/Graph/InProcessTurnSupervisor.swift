import NuumContracts

/// Foreground turns that live with the process, not with one screen.
/// A later supervisor can replace this without putting background policy in Host.
struct InProcessTurnSupervisor: TurnSupervisor {
    func launch(_ block: @escaping @Sendable () async -> Void) -> Task<Void, Never> {
        Task { await block() }
    }
}

/// Built in this file so the name does not collide with `NuumKernel.InProcessTurnSupervisor`.
func makeInProcessTurnSupervisor() -> any TurnSupervisor {
    InProcessTurnSupervisor()
}
