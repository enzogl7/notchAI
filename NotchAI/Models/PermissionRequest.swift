import Foundation

enum PermissionDecision: Sendable {
    case allow
    case deny
    case deferredToAgent
}

struct PermissionRequest: Identifiable, Sendable {
    let id: String
    let agentName: String
    let sessionId: String
    let projectPath: String
    let toolName: String
    let toolInput: [String: String]
    let receivedAt: Date

    var projectName: String {
        URL(fileURLWithPath: projectPath).lastPathComponent
    }

    var summary: String {
        let value = Self.preferredKeys.lazy.compactMap { toolInput[$0] }.first
            ?? toolInput.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.first
        return Self.condense(value ?? toolName)
    }

    private static let preferredKeys = [
        "command",
        "file_path",
        "url",
        "pattern",
        "path",
        "query",
        "prompt",
        "description"
    ]

    private static func condense(_ text: String, limit: Int = 160) -> String {
        let flat = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return flat.count <= limit ? flat : String(flat.prefix(limit - 1)) + "…"
    }
}
