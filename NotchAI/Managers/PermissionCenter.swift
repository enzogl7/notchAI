import Foundation
import Combine

@MainActor
final class PermissionCenter: ObservableObject {

    static let timeout: TimeInterval = 60

    // ponytail: AskUserQuestion chega por este mesmo hook, mas o card só sabe Permitir/Negar.
    // Remover quando a UI de pergunta com alternativas existir.
    private static let skippedTools: Set<String> = ["AskUserQuestion"]

    @Published private(set) var pending: [PermissionRequest] = []

    private let responder: PermissionResponder
    private var timers: [String: Timer] = [:]

    init(responder: PermissionResponder) {
        self.responder = responder
    }

    func handle(_ event: HookEvent) {
        guard event.hookType == EventServer.permissionHook else { return }

        let id = event.requestId
        let request = PermissionRequest(
            id: id,
            agentName: "Claude",
            sessionId: event.sessionId ?? id,
            projectPath: event.cwd ?? "",
            toolName: event.toolName ?? "?",
            toolInput: event.toolInput,
            receivedAt: Date()
        )

        guard !Self.skippedTools.contains(request.toolName) else {
            responder.respond(to: request, decision: .deferredToAgent)
            return
        }

        pending.append(request)
        timers[id] = Timer.scheduledTimer(withTimeInterval: Self.timeout, repeats: false) { _ in
            MainActor.assumeIsolated { self.resolve(id, decision: .deferredToAgent) }
        }
    }

    func allow(_ request: PermissionRequest) {
        resolve(request.id, decision: .allow)
    }

    func deny(_ request: PermissionRequest) {
        resolve(request.id, decision: .deny)
    }

    private func resolve(_ id: String, decision: PermissionDecision) {
        timers.removeValue(forKey: id)?.invalidate()
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return }
        let request = pending.remove(at: index)
        responder.respond(to: request, decision: decision)
    }
}
