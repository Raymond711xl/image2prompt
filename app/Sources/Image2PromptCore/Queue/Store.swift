import Foundation
import SQLite3

/// 本地库：把队列、StyleSpec、Brief 存到磁盘，关掉 App 再打开还在。
///
/// 用系统自带的 SQLite3（`import SQLite3`），不引第三方依赖——少一个依赖就少一份
/// 分发和升级的麻烦，而这里用到的功能 C API 完全够。
///
/// **原图全程只读**：库里只存路径，绝不复制、移动或改写原图。图被移走了就标记丢失，
/// 由用户决定重新关联还是移除。
public final class Store {

    public enum StoreError: Error, LocalizedError {
        case cannotOpen(String)
        case sql(String)

        public var errorDescription: String? {
            switch self {
            case .cannotOpen(let path): return "打不开数据库：\(path)"
            case .sql(let message): return "数据库错误：\(message)"
            }
        }
    }

    /// sqlite3_bind_text 需要它来告诉 SQLite 复制一份字符串。
    /// C 宏在 Swift 里不可见，只能这样重建。
    private static let transient = unsafeBitCast(
        -1, to: sqlite3_destructor_type.self)

    private var db: OpaquePointer?
    public let url: URL

    /// 默认落在 Application Support 下，跟着 bundle id 走
    public static func defaultURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent("com.raymond711xl.image2prompt", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("library.sqlite")
    }

    public init(url: URL) throws {
        self.url = url
        guard sqlite3_open(url.path, &db) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close(db)
            throw StoreError.cannotOpen("\(url.path) — \(message)")
        }
        try exec("PRAGMA journal_mode = WAL;")
        try exec("PRAGMA foreign_keys = ON;")
        try migrate()
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    // MARK: - 迁移

    private func migrate() throws {
        try exec(
            """
            CREATE TABLE IF NOT EXISTS items (
                id            TEXT PRIMARY KEY,
                image_path    TEXT NOT NULL UNIQUE,
                added_at      REAL NOT NULL,
                status        TEXT NOT NULL,
                status_detail TEXT,
                spec_json     TEXT,
                brief_text    TEXT NOT NULL DEFAULT '',
                brief_json    TEXT
            );
            """)
        try exec("CREATE INDEX IF NOT EXISTS idx_items_added ON items(added_at);")
        try exec("CREATE INDEX IF NOT EXISTS idx_items_status ON items(status);")
        // schema_version 为将来的迁移留个把手
        try exec("PRAGMA user_version = 1;")
    }

    // MARK: - 读写

    public func upsert(_ item: QueueItem) throws {
        let sql = """
            INSERT INTO items (id, image_path, added_at, status, status_detail, spec_json, brief_text, brief_json)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
            ON CONFLICT(image_path) DO UPDATE SET
                status = excluded.status,
                status_detail = excluded.status_detail,
                spec_json = excluded.spec_json,
                brief_text = excluded.brief_text,
                brief_json = excluded.brief_json;
            """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }

        let (status, detail) = Self.encode(item.status)
        bindText(statement, 1, item.id.uuidString)
        bindText(statement, 2, item.imageURL.standardizedFileURL.path)
        sqlite3_bind_double(statement, 3, item.addedAt.timeIntervalSince1970)
        bindText(statement, 4, status)
        bindText(statement, 5, detail)
        bindText(statement, 6, item.spec.flatMap { try? String(data: $0.encoded(), encoding: .utf8) } ?? nil)
        bindText(statement, 7, item.briefText)
        bindText(
            statement, 8,
            item.brief.flatMap { try? JSONEncoder().encode($0) }
                .flatMap { String(data: $0, encoding: .utf8) })

        guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError() }
    }

    public func loadAll() throws -> [QueueItem] {
        let statement = try prepare(
            """
            SELECT id, image_path, added_at, status, status_detail, spec_json, brief_text, brief_json
            FROM items ORDER BY added_at ASC;
            """)
        defer { sqlite3_finalize(statement) }

        var out: [QueueItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let path = text(statement, 1) else { continue }
            let item = QueueItem(
                id: text(statement, 0).flatMap(UUID.init(uuidString:)) ?? UUID(),
                imageURL: URL(fileURLWithPath: path),
                addedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
            )
            item.status = Self.decode(text(statement, 3) ?? "waiting", detail: text(statement, 4))
            item.spec = text(statement, 5)
                .flatMap { try? StyleSpec.decode(from: Data($0.utf8)) }
            item.briefText = text(statement, 6) ?? ""
            item.brief = text(statement, 7)
                .flatMap { try? JSONDecoder().decode(Brief.self, from: Data($0.utf8)) }
            out.append(item)
        }
        return out
    }

    public func delete(id: UUID) throws {
        let statement = try prepare("DELETE FROM items WHERE id = ?1;")
        defer { sqlite3_finalize(statement) }
        bindText(statement, 1, id.uuidString)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError() }
    }

    public func deleteAll() throws {
        try exec("DELETE FROM items;")
    }

    public var count: Int {
        guard let statement = try? prepare("SELECT COUNT(*) FROM items;") else { return 0 }
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_ROW ? Int(sqlite3_column_int(statement, 0)) : 0
    }

    // MARK: - 状态编解码

    /// 「分析中」不落库为分析中：进程都没了，那次分析必然没跑完。
    /// 重开时它应该回到「等待」，而不是显示一个永远转不完的圈。
    static func encode(_ status: AnalysisStatus) -> (String, String?) {
        switch status {
        case .waiting, .analyzing: return ("waiting", nil)
        case .done: return ("done", nil)
        case .failed(let message): return ("failed", message)
        }
    }

    static func decode(_ raw: String, detail: String?) -> AnalysisStatus {
        switch raw {
        case "done": return .done
        case "failed": return .failed(detail ?? "未知错误")
        default: return .waiting
        }
    }

    // MARK: - C API 包装

    private func exec(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw lastError() }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError()
        }
        return statement
    }

    private func bindText(_ statement: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(statement, index, value, -1, Self.transient)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func text(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard let cString = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: cString)
    }

    private func lastError() -> StoreError {
        .sql(db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown")
    }
}
