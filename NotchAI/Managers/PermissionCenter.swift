import Foundation
import Combine

@MainActor
final class PermissionCenter: ObservableObject {

    static let timeout: TimeInterval = 60

    @Published private(set) var pending: [AgentRequest] = []

    private let responder: PermissionResponder
    private var timers: [String: Timer] = [:]

    init(responder: PermissionResponder) {
        self.responder = responder
    }

    func handle(_ event: HookEvent) {
        guard event.hookType == EventServer.permissionHook else { return }

        let request = AgentRequest(event: event)

        guard !request.options.isEmpty else {
            responder.respond(to: request, choice: nil)
            return
        }

        pending.append(request)
        timers[request.id] = Timer.scheduledTimer(withTimeInterval: Self.timeout, repeats: false) { _ in
            MainActor.assumeIsolated { self.resolve(request.id, choice: nil) }
        }
    }

    func choose(_ option: AgentRequest.Option, for request: AgentRequest) {
        resolve(request.id, choice: option)
    }

    private func resolve(_ id: String, choice: AgentRequest.Option?) {
        timers.removeValue(forKey: id)?.invalidate()
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return }
        let request = pending.remove(at: index)
        responder.respond(to: request, choice: choice)
    }
}
