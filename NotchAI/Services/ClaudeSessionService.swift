import Foundation

struct ClaudeSessionService: Sendable {

    private let agentName = "Claude"
    private let projectsURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appending(path: ".claude/projects")

    private let activeWindow: TimeInterval = 600
    private let workingWindow: TimeInterval = 15
    private let idleWindow: TimeInterval = 120
    private let prefixByteLimit = 64 * 1024

    func activeSessions(now: Date = Date()) -> [AgentSession] {
        let fileManager = FileManager.default

        guard let projectDirs = try? fileManager.contentsOfDirectory(
            at: projectsURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var sessions: [AgentSession] = []

        for projectDir in projectDirs {
            guard let files = try? fileManager.contentsOfDirectory(
                at: projectDir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for file in files where file.pathExtension == "jsonl" {
                guard let modified = modificationDate(of: file) else { continue }

                let elapsed = now.timeIntervalSince(modified)
                guard elapsed <= activeWindow,
                      let meta = metadata(of: file) else { continue }

                sessions.append(
                    AgentSession(
                        id: file.deletingPathExtension().lastPathComponent,
                        agentName: agentName,
                        projectPath: meta.cwd,
                        gitBranch: meta.gitBranch,
                        state: state(forElapsed: elapsed),
                        lastActivity: modified
                    )
                )
            }
        }

        return sessions.sorted { $0.lastActivity > $1.lastActivity }
    }

    private func state(forElapsed elapsed: TimeInterval) -> SessionState {
        switch elapsed {
        case ..<workingWindow: .working
        case ..<idleWindow: .waitingForInput
        default: .idle
        }
    }

    private func modificationDate(of url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private func metadata(of url: URL) -> (cwd: String, gitBranch: String?)? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        guard let data = try? handle.read(upToCount: prefixByteLimit),
              let text = String(data: data, encoding: .utf8) else { return nil }

        for line in text.split(separator: "\n") {
            guard let lineData = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let cwd = object["cwd"] as? String else { continue }

            return (cwd, object["gitBranch"] as? String)
        }

        return nil
    }
}
