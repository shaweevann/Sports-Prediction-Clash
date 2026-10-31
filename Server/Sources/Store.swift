import Foundation
import SQLite3

/// A thin SQLite wrapper. Every call runs on the service's one queue, so there is no locking here.
final class Store {
    private var db: OpaquePointer?

    /// `path` ":memory:" gives a throwaway database for tests.
    init(path: String) throws {
        guard sqlite3_open(path, &db) == SQLITE_OK else { throw StoreError.sql("can't open \(path)") }
        try exec("PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON;")
        try exec("""
            CREATE TABLE IF NOT EXISTS users (
              id TEXT PRIMARY KEY,
              token_hash TEXT NOT NULL UNIQUE,
              name TEXT NOT NULL,
              created_at INTEGER NOT NULL
            );
            -- Trophies only move as ledger rows; a balance is the sum of a player's rows.
            CREATE TABLE IF NOT EXISTS ledger (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              user_id TEXT NOT NULL REFERENCES users(id),
              amount INTEGER NOT NULL,
              reason TEXT NOT NULL,
              ref TEXT,
              created_at INTEGER NOT NULL
            );
            CREATE INDEX IF NOT EXISTS ledger_user ON ledger(user_id);
            -- A reward can be paid once: mission claims use ref "mission:<day>:<id>".
            CREATE UNIQUE INDEX IF NOT EXISTS ledger_once ON ledger(user_id, ref) WHERE reason = 'mission';
            CREATE TABLE IF NOT EXISTS games (
              user_id TEXT NOT NULL REFERENCES users(id),
              game_id TEXT NOT NULL,
              state TEXT NOT NULL,
              PRIMARY KEY (user_id, game_id)
            );
            -- One slip per player per drive: the first snap is the only one that counts.
            CREATE TABLE IF NOT EXISTS slips (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              user_id TEXT NOT NULL REFERENCES users(id),
              game_id TEXT NOT NULL,
              drive INTEGER NOT NULL,
              legs TEXT NOT NULL,
              stake INTEGER NOT NULL,
              mult REAL NOT NULL,
              won INTEGER NOT NULL,
              payout INTEGER NOT NULL,
              created_at INTEGER NOT NULL,
              UNIQUE (user_id, game_id, drive)
            );
            """)
    }

    deinit { sqlite3_close(db) }

    func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(err)
            throw StoreError.sql(msg)
        }
    }

    /// Runs `body` in a transaction: all of it lands, or none of it.
    func transaction<T>(_ body: () throws -> T) throws -> T {
        try exec("BEGIN IMMEDIATE")
        do {
            let value = try body()
            try exec("COMMIT")
            return value
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }

    @discardableResult
    func run(_ sql: String, _ args: [Any?] = []) throws -> Int64 {
        let stmt = try prepare(sql, args)
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_step(stmt)
        if rc == SQLITE_CONSTRAINT { throw StoreError.constraint }
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else { throw StoreError.sql(message) }
        return sqlite3_last_insert_rowid(db)
    }

    /// Each row as an array of column values: Int64, Double, String or nil.
    func rows(_ sql: String, _ args: [Any?] = []) throws -> [[Any?]] {
        let stmt = try prepare(sql, args)
        defer { sqlite3_finalize(stmt) }
        var out: [[Any?]] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw StoreError.sql(message) }
            out.append((0..<sqlite3_column_count(stmt)).map { i -> Any? in
                switch sqlite3_column_type(stmt, i) {
                case SQLITE_INTEGER: return sqlite3_column_int64(stmt, i)
                case SQLITE_FLOAT: return sqlite3_column_double(stmt, i)
                case SQLITE_TEXT: return String(cString: sqlite3_column_text(stmt, i))
                default: return nil
                }
            })
        }
        return out
    }

    private var message: String { String(cString: sqlite3_errmsg(db)) }

    private func prepare(_ sql: String, _ args: [Any?]) throws -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw StoreError.sql(message) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (i, a) in args.enumerated() {
            let idx = Int32(i + 1)
            switch a {
            case nil: sqlite3_bind_null(stmt, idx)
            case let v as Int: sqlite3_bind_int64(stmt, idx, Int64(v))
            case let v as Int64: sqlite3_bind_int64(stmt, idx, v)
            case let v as Double: sqlite3_bind_double(stmt, idx, v)
            case let v as Bool: sqlite3_bind_int64(stmt, idx, v ? 1 : 0)
            case let v as String: sqlite3_bind_text(stmt, idx, v, -1, transient)
            default:
                sqlite3_finalize(stmt)
                throw StoreError.sql("can't bind \(type(of: a))")
            }
        }
        return stmt
    }
}

enum StoreError: Error {
    case sql(String)
    case constraint
}
