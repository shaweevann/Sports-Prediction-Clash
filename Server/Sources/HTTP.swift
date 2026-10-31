import Foundation
import Network

struct Request {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    var bearer: String? {
        guard let h = headers["authorization"], h.lowercased().hasPrefix("bearer ") else { return nil }
        return String(h.dropFirst(7))
    }
}

struct Response {
    var status: Int
    var body: Data
    var contentType = "application/json"

    static func json<T: Encodable>(_ value: T, status: Int = 200) -> Response {
        Response(status: status, body: (try? JSONEncoder().encode(value)) ?? Data())
    }
    static func error(_ status: Int, _ message: String) -> Response { .json(ErrorReply(error: message), status: status) }
}

/// A small HTTP/1.1 server: one request per connection, then close. Enough for the app and local testing;
/// production sits behind a proper gateway (see the architecture doc).
final class HTTPServer {
    private let listener: NWListener
    private let queue: DispatchQueue
    private let handle: (Request) -> Response
    private static let maxBody = 64 * 1024

    init(port: UInt16, queue: DispatchQueue, handle: @escaping (Request) -> Response) throws {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        listener = try NWListener(using: params)
        self.queue = queue; self.handle = handle
    }

    func start(ready: @escaping () -> Void) {
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready: ready()
            case .failed(let e): fatalError("Server failed: \(e)")
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] conn in
            guard let self else { return }
            conn.start(queue: self.queue)
            self.read(conn, Data())
        }
        listener.start(queue: queue)
    }

    private func read(_ conn: NWConnection, _ buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, done, error in
            guard let self else { return }
            var buf = buffer
            if let data { buf.append(data) }
            if error != nil { conn.cancel(); return }
            switch Self.parse(buf) {
            case .some(.success(let req)): self.reply(conn, self.handle(req))
            case .some(.failure): self.reply(conn, .error(400, "Bad request."))
            case .none: done ? conn.cancel() : self.read(conn, buf)
            }
        }
    }

    private func reply(_ conn: NWConnection, _ res: Response) {
        let head = "HTTP/1.1 \(res.status) \(Self.reason(res.status))\r\nContent-Type: \(res.contentType)\r\nContent-Length: \(res.body.count)\r\nConnection: close\r\n\r\n"
        conn.send(content: Data(head.utf8) + res.body, completion: .contentProcessed { _ in conn.cancel() })
    }

    /// nil until the whole request has arrived.
    private static func parse(_ buf: Data) -> Result<Request, ParseError>? {
        guard let end = buf.range(of: Data("\r\n\r\n".utf8)) else {
            return buf.count > 16 * 1024 ? .failure(ParseError()) : nil
        }
        guard let head = String(data: buf[..<end.lowerBound], encoding: .utf8) else { return .failure(ParseError()) }
        var lines = head.components(separatedBy: "\r\n")
        let start = lines.removeFirst().split(separator: " ")
        guard start.count == 3 else { return .failure(ParseError()) }
        var headers: [String: String] = [:]
        for l in lines {
            guard let c = l.firstIndex(of: ":") else { continue }
            headers[l[..<c].lowercased()] = l[l.index(after: c)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? -1
        guard (0...maxBody).contains(length) else { return .failure(ParseError()) }
        let body = buf[end.upperBound...]
        guard body.count >= length else { return nil }
        let path = String(start[1].split(separator: "?").first ?? "")
        return .success(Request(method: String(start[0]), path: path, headers: headers, body: Data(body.prefix(length))))
    }

    private static func reason(_ s: Int) -> String {
        [200: "OK", 201: "Created", 400: "Bad Request", 401: "Unauthorized", 402: "Payment Required", 404: "Not Found",
         409: "Conflict", 500: "Internal Server Error"][s] ?? "Status"
    }

    struct ParseError: Error {}
}
