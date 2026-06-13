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
    private var timer: Timer?

    func startMonitoring() {

        guard timer == nil else { return }

        updateAgents()

        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in
                self.updateAgents()
            }
        }
    }

    private func updateAgents() {

        let snapshot = agents
        let monitor = monitor
        let sessionService = sessionService

        Task.detached(priority: .utility) {
            let updated = snapshot.map { agent -> Agent in
                var agent = agent
                agent.isRunning = monitor.isProcessRunning(named: agent.processName)
                return agent
            }

            let sessions = sessionService.activeSessions()

            await MainActor.run {
                self.agents = updated
                self.sessions = sessions
            }
        }
    }
}
