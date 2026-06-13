import Foundation

enum SessionState: Sendable {
    case working
    case waitingForInput
    case waitingForPermission
    case idle
}

struct AgentSession: Identifiable, Sendable {
    let id: String
    let agentName: String
    let projectPath: String
    let gitBranch: String?
    let state: SessionState
    let lastActivity: Date

    var projectName: String {
        URL(fileURLWithPath: projectPath).lastPathComponent
    }
}
