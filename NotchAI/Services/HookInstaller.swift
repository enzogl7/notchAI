import Foundation

struct HookInstaller {

    private static let settingsURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appending(path: ".claude/settings.json")

    private static let marker = "127.0.0.1:7749/NotchAI"
    private static let versionedMarker = "\(marker)/v2"

    private static let hookTypes = [
        "PreToolUse",
        "PostToolUse",
        "Stop",
        "Notification",
        EventServer.permissionHook
    ]

    private static func command(for hookType: String) -> String {
        "curl -sf -X POST 'http://\(versionedMarker)/\(hookType)' -H 'Content-Type: application/json' -d @- || true"
    }

    static var areInstalled: Bool {
        guard let data = try? Data(contentsOf: settingsURL),
              let text = String(data: data, encoding: .utf8) else { return false }
        return text.contains(versionedMarker)
    }

    static func install() throws {
        var settings = load()
        backup()

        var hooks = stripped(settings["hooks"] as? [String: Any] ?? [:])

        for hookType in hookTypes {
            var entries = hooks[hookType] as? [[String: Any]] ?? []
            entries.append(["hooks": [["type": "command", "command": command(for: hookType)]]])
            hooks[hookType] = entries
        }

        settings["hooks"] = hooks
        try write(settings)
    }

    static func remove() throws {
        var settings = load()
        let hooks = stripped(settings["hooks"] as? [String: Any] ?? [:])
        settings["hooks"] = hooks.isEmpty ? nil : hooks
        try write(settings)
    }

    private static func stripped(_ hooks: [String: Any]) -> [String: Any] {
        hooks.compactMapValues { value in
            guard var entries = value as? [[String: Any]] else { return value }
            entries.removeAll { entry in
                (entry["hooks"] as? [[String: Any]])?.contains {
                    ($0["command"] as? String)?.contains(marker) == true
                } == true
            }
            return entries.isEmpty ? nil : entries
        }
    }

    private static func load() -> [String: Any] {
        guard let data = try? Data(contentsOf: settingsURL),
              let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return settings
    }

    private static func backup() {
        guard let data = try? Data(contentsOf: settingsURL) else { return }
        let backupURL = settingsURL.deletingPathExtension().appendingPathExtension("notchai-backup.json")
        try? data.write(to: backupURL)
    }

    private static func write(_ settings: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: settingsURL)
    }
}
