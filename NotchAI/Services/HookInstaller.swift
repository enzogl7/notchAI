import Foundation

struct HookInstaller {

    private static let settingsURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appending(path: ".claude/settings.json")

    private static let marker = "127.0.0.1:7749/NotchAI"
    private static let versionedMarker = "\(marker)/v3"
    private static let originalStatusLineKey = "originalStatusLineCommand"

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
        settings["statusLine"] = installedStatusLine(settings["statusLine"] as? [String: Any])
        try write(settings)
    }

    static func remove() throws {
        var settings = load()
        let hooks = stripped(settings["hooks"] as? [String: Any] ?? [:])
        settings["hooks"] = hooks.isEmpty ? nil : hooks
        settings["statusLine"] = restoredStatusLine(settings["statusLine"] as? [String: Any])
        try write(settings)
    }

    private static func installedStatusLine(_ current: [String: Any]?) -> [String: Any] {
        var statusLine = current ?? ["type": "command"]
        let existing = statusLine["command"] as? String

        if existing?.contains(marker) != true {
            UserDefaults.standard.set(existing, forKey: originalStatusLineKey)
        }

        let original = UserDefaults.standard.string(forKey: originalStatusLineKey)
        let post = "curl -sf -m 2 -X POST 'http://\(versionedMarker)/\(EventServer.statusLinePath)'"
            + " -H 'Content-Type: application/json' -d @- >/dev/null 2>&1"
        var command = "p=$(cat); printf '%s' \"$p\" | \(post) &"
        if let original, !original.isEmpty {
            command += " printf '%s' \"$p\" | \(original)"
        }

        statusLine["command"] = command
        return statusLine
    }

    private static func restoredStatusLine(_ current: [String: Any]?) -> [String: Any]? {
        guard var statusLine = current,
              (statusLine["command"] as? String)?.contains(marker) == true else { return current }

        defer { UserDefaults.standard.removeObject(forKey: originalStatusLineKey) }

        guard let original = UserDefaults.standard.string(forKey: originalStatusLineKey),
              !original.isEmpty else { return nil }

        statusLine["command"] = original
        return statusLine
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
