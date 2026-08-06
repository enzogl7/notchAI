import Foundation
import Network

struct HookEvent: Sendable {
    let hookType: String
    let requestId: String
    let sessionId: String?
    let toolName: String?
    let toolInput: [String: String]
    let cwd: String?
    let permissionMode: String?
    let notificationType: String?
    let transcriptPath: String?
}

final class EventServer: @unchecked Sendable {

    static let port: UInt16 = 7749
    static let permissionHook = "PermissionRequest"

    var onEvent: ((HookEvent) -> Void)?

    private var listener: NWListener?
    private let lock = NSLock()
    private var deferred: [String: NWConnection] = [:]

    func start() {
        guard let port = NWEndpoint.Port(rawValue: Self.port),
              let listener = try? NWListener(using: .tcp, on: port) else { return }

        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: .global(qos: .utility))
            self?.receive(on: connection, buffer: Data())
        }
        listener.start(queue: .global(qos: .utility))
        self.listener = listener
    }

    func stop() {
        let connections = lock.withLock { () -> [NWConnection] in
            let values = Array(deferred.values)
            deferred.removeAll()
            return values
        }
        for connection in connections { send(nil, on: connection) }

        listener?.cancel()
        listener = nil
    }

    func respond(requestId: String, json: String?) {
        guard let connection = lock.withLock({ deferred.removeValue(forKey: requestId) }) else { return }
        send(json, on: connection)
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            var buffer = buffer
            if let data { buffer.append(data) }

            guard error == nil else { return connection.cancel() }

            guard let request = Self.parse(buffer) else {
                if isComplete { connection.cancel() } else { self.receive(on: connection, buffer: buffer) }
                return
            }

            self.process(request, on: connection)
        }
    }

    private func process(_ request: Request, on connection: NWConnection) {
        guard let event = Self.decode(body: request.body, hookType: request.hookType) else {
            return send(nil, on: connection)
        }

        if event.hookType == Self.permissionHook {
            lock.withLock { deferred[event.requestId] = connection }
            onEvent?(event)
            return
        }

        onEvent?(event)
        send(nil, on: connection)
    }

    private func send(_ json: String?, on connection: NWConnection) {
        let body = Data((json ?? "").utf8)
        let head = """
        HTTP/1.1 200 OK\r
        Content-Type: application/json\r
        Content-Length: \(body.count)\r
        Connection: close\r
        \r

        """
        connection.send(
            content: Data(head.utf8) + body,
            completion: .contentProcessed { _ in connection.cancel() }
        )
    }

    private struct Request {
        let hookType: String
        let body: Data
    }

    private static func parse(_ data: Data) -> Request? {
        let separator = Data([0x0D, 0x0A, 0x0D, 0x0A])
        guard let range = data.range(of: separator),
              let head = String(data: data[..<range.lowerBound], encoding: .utf8) else { return nil }

        let lines = head.components(separatedBy: "\r\n")
        let target = lines.first?.components(separatedBy: " ").dropFirst().first
        guard let hookType = target?.split(separator: "/").last.map(String.init) else { return nil }

        let body = Data(data[range.upperBound...])
        if let contentLength = lines.dropFirst().compactMap(Self.contentLength).first, body.count < contentLength {
            return nil
        }

        return Request(hookType: hookType, body: body)
    }

    private static func contentLength(in headerLine: String) -> Int? {
        let parts = headerLine.split(separator: ":", maxSplits: 1)
        guard parts.count == 2, parts[0].lowercased() == "content-length" else { return nil }
        return Int(parts[1].trimmingCharacters(in: .whitespaces))
    }

    private static func decode(body: Data, hookType: String) -> HookEvent? {
        guard !body.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }

        return HookEvent(
            hookType: hookType,
            requestId: UUID().uuidString,
            sessionId: json["session_id"] as? String,
            toolName: json["tool_name"] as? String,
            toolInput: flatten(json["tool_input"] as? [String: Any] ?? [:]),
            cwd: json["cwd"] as? String,
            permissionMode: json["permission_mode"] as? String,
            notificationType: json["notification_type"] as? String,
            transcriptPath: json["transcript_path"] as? String
        )
    }

    private static func flatten(_ input: [String: Any]) -> [String: String] {
        input.compactMapValues { value in
            if let string = value as? String { return string }
            if let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]) {
                return String(data: data, encoding: .utf8)
            }
            return nil
        }
    }
}
