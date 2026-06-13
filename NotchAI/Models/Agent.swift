import Foundation

struct Agent: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let processName: String
    let icon: String
    var isRunning: Bool
}

extension Agent {

    static let builtIn: [Agent] = [
        Agent(name: "Claude",   processName: "claude",   icon: "brain",           isRunning: false),
        Agent(name: "Codex",    processName: "codex",    icon: "chevron.left.forwardslash.chevron.right", isRunning: false),
        Agent(name: "Gemini",   processName: "gemini",   icon: "sparkles",        isRunning: false),
        Agent(name: "OpenCode", processName: "opencode", icon: "curlybraces",     isRunning: false)
    ]
}
