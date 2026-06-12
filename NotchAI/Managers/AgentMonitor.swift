import Foundation
import Combine

@MainActor
final class AgentMonitor: ObservableObject {

    @Published var agents: [Agent] = [
        Agent(name: "Claude", isRunning: false),
        Agent(name: "Codex", isRunning: false),
        Agent(name: "Gemini", isRunning: false),
        Agent(name: "OpenCode", isRunning: false)
    ]

    private let monitor = ProcessMonitorService()
    private var timer: Timer?

    func startMonitoring() {

        updateAgents()

        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            self.updateAgents()
        }
    }

    private func updateAgents() {

        agents[0].isRunning = monitor.isProcessRunning(named: "claude")
        agents[1].isRunning = monitor.isProcessRunning(named: "codex")
        agents[2].isRunning = monitor.isProcessRunning(named: "gemini")
        agents[3].isRunning = monitor.isProcessRunning(named: "opencode")
    }
}
