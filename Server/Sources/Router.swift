import Foundation

/// Maps requests to the service. Every route but account creation needs `Authorization: Bearer <token>`.
struct Router {
    let service: Service

    func handle(_ req: Request) -> Response {
        do {
            switch (req.method, req.path) {
            case ("GET", "/v1/health"):
                return .json(["ok": true])
            case ("POST", "/v1/accounts"):
                let body = req.body.isEmpty ? AccountRequest() : try decode(AccountRequest.self, req)
                return .json(try service.createAccount(name: body.name), status: 201)
            case ("GET", "/v1/me"):
                return .json(try service.me(try auth(req)))
            case ("GET", "/v1/feed"):
                return .json(try service.feed(try auth(req)))
            case ("POST", "/v1/snap"):
                let u = try auth(req)
                return .json(try service.snap(u, try decode(SnapRequest.self, req)))
            case ("GET", "/v1/ledger"):
                return .json(try service.ledger(try auth(req)))
            case ("POST", "/v1/missions/claim"):
                let u = try auth(req)
                return .json(try service.claim(u, try decode(ClaimRequest.self, req)))
            default:
                return .error(404, "No such route.")
            }
        } catch let e as ServiceError {
            return .error(e.status, e.message)
        } catch is DecodingError {
            return .error(400, "The request body isn't in the expected shape.")
        } catch {
            print("error on \(req.method) \(req.path): \(error)")
            return .error(500, "Something went wrong on the server.")
        }
    }

    private func auth(_ req: Request) throws -> User {
        guard let token = req.bearer, let u = try service.user(token: token) else {
            throw ServiceError(status: 401, message: "Sign in again.")
        }
        return u
    }

    private func decode<T: Decodable>(_ type: T.Type, _ req: Request) throws -> T {
        try JSONDecoder().decode(type, from: req.body)
    }
}
