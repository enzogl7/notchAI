import Foundation
import Network

struct HookEvent: Sendable {
    let hookType: String
    let sessionId: String?
    let toolName: String?
    let transcriptPath: String?
}

final class EventServer: @unchecked Sendable {

    static let port: UInt16 = 7749

    var onEvent: ((HookEvent) -> Void)?

    private var listener: NWListener?

    func start() {
        guard let port = NWEndpoint.Port(rawValue: Self.port),
              let listener = try? NWListener(using: .tcp, on: port) else { return }

        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.start(queue: .global(qos: .utility))
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .utility))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in
            if let data, let (hookType, body) = Self.parse(data),
               let event = Self.decode(body: body, hookType: hookType) {
                self?.onEvent?(event)
            }
            let response = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private static func parse(_ data: Data) -> (hookType: String, body: Data)? {
        guard let text = String(data: data, encoding: .utf8),
              let requestLine = text.components(separatedBy: "\r\n").first else { return nil }

        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return nil }
        let hookType = String(parts[1].dropFirst())

        let separator = Data([0x0D, 0x0A, 0x0D, 0x0A])
        guard let range = data.range(of: separator) else { return nil }
        return (hookType, Data(data[range.upperBound...]))
    }

    private static func decode(body: Data, hookType: String) -> HookEvent? {
        guard !body.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
        return HookEvent(
            hookType: hookType,
            sessionId: json["session_id"] as? String,
            toolName: json["tool_name"] as? String,
            transcriptPath: json["transcript_path"] as? String
        )
    }
}
