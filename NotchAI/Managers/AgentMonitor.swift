import Foundation
import Combine

@MainActor
final class AgentMonitor: ObservableObject {

    @Published var agents: [Agent] = Agent.builtIn
    @Published var sessions: [AgentSession] = []

    static let liveWorkingWindow: TimeInterval = 15

    let permissionCenter: PermissionCenter

    var activeCount: Int {
        agents.filter(\.isRunning).count
    }

    private let monitor = ProcessMonitorService()
    private let sessionService = ClaudeSessionService()
    private let eventServer: EventServer
    private var awaitingPermission: Set<String> = []
    private var liveStates: [String: LiveState] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var timer: Timer?

    private struct LiveState {
        let state: SessionState
        let at: Date
    }

    init() {
        let server = EventServer()
        eventServer = server
        permissionCenter = PermissionCenter(responder: ClaudeHookResponder(server: server))
    }

    func startMonitoring() {
        guard timer == nil else { return }

        eventServer.onEvent = { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        eventServer.start()

        permissionCenter.$pending
            .map { Set($0.map(\.sessionId)) }
            .removeDuplicates()
            .sink { [weak self] sessionIds in
                self?.awaitingPermission = sessionIds
                self?.refreshStates()
            }
            .store(in: &cancellables)

        if !HookInstaller.areInstalled {
            try? HookInstaller.install()
        }

        updateAgents()

        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in self.updateAgents() }
        }
    }

    func removeHooks() {
        try? HookInstaller.remove()
    }

    private func handle(_ event: HookEvent) {
        permissionCenter.handle(event)

        guard let sessionId = event.sessionId else { return }

        let state: SessionState? = switch event.hookType {
        case "PreToolUse", "PostToolUse": .working
        case "Stop": .idle
        case "Notification" where event.notificationType == "idle_prompt": .waitingForInput
        default: nil
        }

        guard let state else { return }
        liveStates[sessionId] = LiveState(state: state, at: Date())
        refreshStates()
    }

    private func updateAgents() {
        let snapshot = agents
        let monitor = monitor
        let sessionService = sessionService

        Task.detached(priority: .utility) {
            let updated = snapshot.map { agent -> Agent in
                var a = agent
                a.isRunning = monitor.isProcessRunning(named: agent.processName)
                return a
            }
            let polledSessions = sessionService.activeSessions()

            await MainActor.run {
                self.agents = updated
                self.sessions = self.decorate(polledSessions)
            }
        }
    }

    private func refreshStates() {
        sessions = decorate(sessions)
    }

    private func decorate(_ sessions: [AgentSession]) -> [AgentSession] {
        sessions.map { session in
            let state = resolvedState(for: session)
            guard state != session.state else { return session }
            return AgentSession(
                id: session.id,
                agentName: session.agentName,
                projectPath: session.projectPath,
                gitBranch: session.gitBranch,
                state: state,
                lastActivity: session.lastActivity
            )
        }
    }

    private func resolvedState(for session: AgentSession) -> SessionState {
        if awaitingPermission.contains(session.id) { return .waitingForPermission }

        guard let live = liveStates[session.id], live.at >= session.lastActivity else {
            return session.state == .waitingForPermission ? .working : session.state
        }

        if live.state == .working, Date().timeIntervalSince(live.at) > Self.liveWorkingWindow {
            return session.state
        }

        return live.state
    }
}
