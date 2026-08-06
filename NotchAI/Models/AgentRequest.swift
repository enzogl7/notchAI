import Foundation

struct AgentRequest: Identifiable, Sendable {

    struct Option: Identifiable, Sendable {
        let id: String
        let label: String
        let description: String?
    }

    enum Kind: Sendable {
        case permission
        case question(String)
    }

    let id: String
    let agentName: String
    let sessionId: String
    let projectPath: String
    let toolName: String
    let toolInput: [String: String]
    let rawToolInput: Data?
    let receivedAt: Date
    let kind: Kind
    let options: [Option]

    init(event: HookEvent) {
        id = event.requestId
        agentName = "Claude"
        sessionId = event.sessionId ?? event.requestId
        projectPath = event.cwd ?? ""
        toolName = event.toolName ?? "?"
        toolInput = event.toolInput
        rawToolInput = event.rawToolInput
        receivedAt = Date()

        if event.toolName == Self.questionTool {
            let question = Self.singleChoiceQuestion(in: event.rawToolInput)
            kind = .question(question?.text ?? "")
            options = question?.options ?? []
        } else {
            kind = .permission
            options = Self.permissionOptions
        }
    }

    var projectName: String {
        URL(fileURLWithPath: projectPath).lastPathComponent
    }

    var summary: String {
        if case .question(let text) = kind { return Self.condense(text) }
        let value = Self.preferredKeys.lazy.compactMap { toolInput[$0] }.first
            ?? toolInput.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.first
        return Self.condense(value ?? toolName)
    }

    static let questionTool = "AskUserQuestion"

    static let permissionOptions = [
        Option(id: "deny", label: "Negar", description: nil),
        Option(id: "allow", label: "Permitir", description: nil)
    ]

    private static func singleChoiceQuestion(in data: Data?) -> (text: String, options: [Option])? {
        guard let data,
              let input = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let questions = input["questions"] as? [[String: Any]],
              questions.count == 1,
              let question = questions.first,
              let text = question["question"] as? String,
              !text.isEmpty,
              question["multiSelect"] as? Bool != true,
              let rawOptions = question["options"] as? [[String: Any]],
              !rawOptions.isEmpty else { return nil }

        let options = rawOptions.compactMap { raw -> Option? in
            guard let label = raw["label"] as? String, !label.isEmpty else { return nil }
            return Option(id: label, label: label, description: raw["description"] as? String)
        }

        guard options.count == rawOptions.count else { return nil }
        return (text, options)
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
