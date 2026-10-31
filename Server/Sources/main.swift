import Foundation

// Sports Prediction Clash game server.
//   CLASH_PORT  port to listen on, on 127.0.0.1 only (default 8787)
//   CLASH_DATA  folder for the database and the seed secret (default ./server-data)

let env = ProcessInfo.processInfo.environment
let port = UInt16(env["CLASH_PORT"] ?? "") ?? 8787
let dataDir = URL(fileURLWithPath: env["CLASH_DATA"] ?? "server-data", isDirectory: true)
try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)

/// The seed secret is made once and kept beside the database. Anyone who has it can compute drives ahead of time.
let secretFile = dataDir.appendingPathComponent("secret")
if !FileManager.default.fileExists(atPath: secretFile.path) {
    try Service.randomHex(32).write(to: secretFile, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: secretFile.path)
}
let secret = try String(contentsOf: secretFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)

let service = Service(store: try Store(path: dataDir.appendingPathComponent("clash.sqlite").path), secret: secret)
let router = Router(service: service)
let server = try HTTPServer(port: port, queue: DispatchQueue(label: "clash.server"), handle: router.handle)
server.start { print("Sports Prediction Clash server on http://127.0.0.1:\(port), data in \(dataDir.path)") }
dispatchMain()
