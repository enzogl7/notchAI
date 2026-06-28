import Foundation
import Combine

@MainActor
final class AgentMonitor: ObservableObject {

    @Published var agents: [Agent] = Agent.builtIn
    @Published var sessions: [AgentSession] = []

    var activeCount: Int {
        agents.filter(\.isRunning).count
    }

    private let monitor = ProcessMonitorService()
    private let sessionService = ClaudeSessionService()
    private let eventServer = EventServer()
    private var pendingPermissions: [String: HookEvent] = [:]
    private var timer: Timer?

    func startMonitoring() {
        guard timer == nil else { return }

        eventServer.onEvent = { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        eventServer.start()

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
        guard let sessionId = event.sessionId else { return }
        switch event.hookType {
        case "PreToolUse":
            pendingPermissions[sessionId] = event
        case "PostToolUse", "Stop":
            pendingPermissions.removeValue(forKey: sessionId)
        default:
            break
        }
        applyPendingPermissions()
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
                self.sessions = self.applying(self.pendingPermissions, to: polledSessions)
            }
        }
    }

    private func applyPendingPermissions() {
        sessions = applying(pendingPermissions, to: sessions)
    }

    private func applying(_ pending: [String: HookEvent], to sessions: [AgentSession]) -> [AgentSession] {
        sessions.map { session in
            guard pending[session.id] != nil, session.state != .waitingForPermission else { return session }
            return AgentSession(
                id: session.id,
                agentName: session.agentName,
                projectPath: session.projectPath,
                gitBranch: session.gitBranch,
                state: .waitingForPermission,
                lastActivity: session.lastActivity
            )
        }
    }
}
