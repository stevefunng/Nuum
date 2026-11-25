import NuumProtocol

enum TaskActorRole: Sendable, Equatable, Hashable {
    case user
    case coordinator
    case worker
    case observer
}

private struct TransitionRule {
    var to: WorkTaskState
    var roles: Set<TaskActorRole>
}

/// Single transition table. The work screen and the model tools both read it.
/// Blocked returns to in_progress or ready only for the user.
private let transitions: [WorkTaskState: [TransitionRule]] = [
    .proposed: [
        TransitionRule(to: .ready, roles: [.user, .coordinator]),
        TransitionRule(to: .cancelled, roles: [.user, .coordinator]),
    ],
    .ready: [
        TransitionRule(to: .inProgress, roles: [.user, .coordinator, .worker]),
        TransitionRule(to: .cancelled, roles: [.user, .coordinator]),
    ],
    .inProgress: [
        TransitionRule(to: .review, roles: [.user, .coordinator, .worker]),
        TransitionRule(to: .blocked, roles: [.user, .coordinator, .worker]),
        TransitionRule(to: .cancelled, roles: [.user, .coordinator]),
    ],
    .blocked: [
        TransitionRule(to: .inProgress, roles: [.user]),
        TransitionRule(to: .ready, roles: [.user]),
        TransitionRule(to: .cancelled, roles: [.user, .coordinator]),
    ],
    .review: [
        TransitionRule(to: .done, roles: [.user]),
        TransitionRule(to: .inProgress, roles: [.user, .coordinator]),
        TransitionRule(to: .cancelled, roles: [.user, .coordinator]),
    ],
    .done: [
        TransitionRule(to: .inProgress, roles: [.user, .coordinator]),
    ],
    .cancelled: [],
]

func allowedTaskTransitions(_ state: WorkTaskState, _ role: TaskActorRole) -> [WorkTaskState] {
    (transitions[state] ?? []).filter { $0.roles.contains(role) }.map(\.to)
}

func assertTaskTransition(from: WorkTaskState, to: WorkTaskState, role: TaskActorRole) throws {
    if allowedTaskTransitions(from, role).contains(to) { return }
    throw TaskTransitionError("Transition \(from.rawValue) -> \(to.rawValue) is not allowed for \(role)")
}

struct TaskTransitionError: Error, Sendable, Equatable, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
}

func roleOf(_ role: WorkRole) -> TaskActorRole {
    switch role {
    case .coordinator: .coordinator
    case .worker: .worker
    case .observer: .observer
    }
}
