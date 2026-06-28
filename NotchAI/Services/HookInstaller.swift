import Foundation

struct HookInstaller {

    private static let settingsURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appending(path: ".claude/settings.json")

    private static let marker = "127.0.0.1:7749/NotchAI"

    private static func command(for hookType: String) -> String {
        "curl -sf -X POST 'http://\(marker)/\(hookType)' -H 'Content-Type: application/json' -d @- || true"
    }

    static var areInstalled: Bool {
        guard let data = try? Data(contentsOf: settingsURL),
              let text = String(data: data, encoding: .utf8) else { return false }
        return text.contains(marker)
    }

    static func install() throws {
        var settings: [String: Any] = [:]

        if let data = try? Data(contentsOf: settingsURL) {
            if let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                settings = existing
            }
            let backupURL = settingsURL.deletingPathExtension().appendingPathExtension("notchai-backup.json")
            try? data.write(to: backupURL)
        }

        var hooks = settings["hooks"] as? [String: Any] ?? [:]

        for hookType in ["PreToolUse", "PostToolUse", "Stop", "Notification"] {
            var entries = hooks[hookType] as? [[String: Any]] ?? []
            entries.append(["hooks": [["type": "command", "command": command(for: hookType)]]])
            hooks[hookType] = entries
        }

        settings["hooks"] = hooks

        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: settingsURL)
    }

    static func remove() throws {
        guard let data = try? Data(contentsOf: settingsURL),
              var settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var hooks = settings["hooks"] as? [String: Any] else { return }

        for hookType in ["PreToolUse", "PostToolUse", "Stop", "Notification"] {
            guard var entries = hooks[hookType] as? [[String: Any]] else { continue }
            entries.removeAll { entry in
                (entry["hooks"] as? [[String: Any]])?.contains {
                    ($0["command"] as? String)?.contains(marker) == true
                } == true
            }
            hooks[hookType] = entries.isEmpty ? nil : entries
        }

        hooks = hooks.compactMapValues { $0 }
        settings["hooks"] = hooks.isEmpty ? nil : hooks

        let newData = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try newData.write(to: settingsURL)
    }
}
