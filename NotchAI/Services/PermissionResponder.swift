import Foundation

protocol PermissionResponder: Sendable {
    func respond(to request: AgentRequest, choice: AgentRequest.Option?)
}

struct ClaudeHookResponder: PermissionResponder {

    let server: EventServer

    func respond(to request: AgentRequest, choice: AgentRequest.Option?) {
        server.respond(requestId: request.id, json: Self.payload(for: request, choice: choice))
    }

    static func payload(for request: AgentRequest, choice: AgentRequest.Option?) -> String? {
        guard let choice else { return nil }

        switch request.kind {
        case .permission:
            return wrap(#"{"behavior":"\#(choice.id)"}"#)

        case .question(let text):
            guard let data = request.rawToolInput,
                  var input = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            input["answers"] = [text: choice.label]
            guard let updated = try? JSONSerialization.data(withJSONObject: input),
                  let json = String(data: updated, encoding: .utf8) else { return nil }
            return wrap(#"{"behavior":"allow","updatedInput":\#(json)}"#)
        }
    }

    private static func wrap(_ decision: String) -> String {
        #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":\#(decision)}}"#
    }
}
