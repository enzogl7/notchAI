import Foundation

protocol PermissionResponder: Sendable {
    func respond(to request: PermissionRequest, decision: PermissionDecision)
}

struct ClaudeHookResponder: PermissionResponder {

    let server: EventServer

    func respond(to request: PermissionRequest, decision: PermissionDecision) {
        server.respond(requestId: request.id, json: Self.payload(for: decision))
    }

    private static func payload(for decision: PermissionDecision) -> String? {
        guard let behavior = decision.behavior else { return nil }
        return #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"\#(behavior)"}}}"#
    }
}

private extension PermissionDecision {

    var behavior: String? {
        switch self {
        case .allow: "allow"
        case .deny: "deny"
        case .deferredToAgent: nil
        }
    }
}
