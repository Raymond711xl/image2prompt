import Foundation
import Testing

@testable import FormlessCore

// 改名把数据目录名也改了（目录名 = bundle id）。这几个用例盯的是"老数据不能凭空消失"，
// 而 WAL 模式下"没消失"的判据不是主文件在，是 -wal 也跟着走了——
// 只搬 .sqlite 会丢掉最后一次还没 checkpoint 的写入，表现为"最近分析的几张不见了"。

private func makeTempDir() throws -> URL {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("formless-migration-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func write(_ text: String, to url: URL) throws {
    try text.data(using: .utf8)!.write(to: url)
}

private func read(_ url: URL) -> String? {
    try? String(contentsOf: url, encoding: .utf8)
}

@Test("老目录的库连同 -wal / -shm 一起搬到新目录")
func migratesAllThreeFiles() throws {
    let base = try makeTempDir()
    let legacy = base.appendingPathComponent("legacy")
    let new = base.appendingPathComponent("new")
    let fm = FileManager.default
    try fm.createDirectory(at: legacy, withIntermediateDirectories: true)
    try fm.createDirectory(at: new, withIntermediateDirectories: true)

    try write("db", to: legacy.appendingPathComponent("library.sqlite"))
    try write("wal", to: legacy.appendingPathComponent("library.sqlite-wal"))
    try write("shm", to: legacy.appendingPathComponent("library.sqlite-shm"))

    Store.migrateFromLegacyDirectory(into: new, from: legacy)

    #expect(read(new.appendingPathComponent("library.sqlite")) == "db")
    #expect(read(new.appendingPathComponent("library.sqlite-wal")) == "wal")
    #expect(read(new.appendingPathComponent("library.sqlite-shm")) == "shm")
    // 搬走而不是复制：留一份在老目录，以后哪个版本读到老路径就会看到过期数据
    #expect(!fm.fileExists(atPath: legacy.appendingPathComponent("library.sqlite").path))
}

@Test("新目录已有库时绝不覆盖")
func neverOverwritesExisting() throws {
    let base = try makeTempDir()
    let legacy = base.appendingPathComponent("legacy")
    let new = base.appendingPathComponent("new")
    let fm = FileManager.default
    try fm.createDirectory(at: legacy, withIntermediateDirectories: true)
    try fm.createDirectory(at: new, withIntermediateDirectories: true)

    try write("old", to: legacy.appendingPathComponent("library.sqlite"))
    try write("current", to: new.appendingPathComponent("library.sqlite"))

    Store.migrateFromLegacyDirectory(into: new, from: legacy)

    #expect(read(new.appendingPathComponent("library.sqlite")) == "current")
}

@Test("没有老目录时是空操作，不报错")
func noLegacyIsNoop() throws {
    let base = try makeTempDir()
    let new = base.appendingPathComponent("new")
    try FileManager.default.createDirectory(at: new, withIntermediateDirectories: true)

    Store.migrateFromLegacyDirectory(into: new, from: base.appendingPathComponent("nope"))

    #expect(!FileManager.default.fileExists(atPath: new.appendingPathComponent("library.sqlite").path))
}

@Test("只有主文件、没有 -wal 时也能搬")
func migratesWithoutWal() throws {
    let base = try makeTempDir()
    let legacy = base.appendingPathComponent("legacy")
    let new = base.appendingPathComponent("new")
    let fm = FileManager.default
    try fm.createDirectory(at: legacy, withIntermediateDirectories: true)
    try fm.createDirectory(at: new, withIntermediateDirectories: true)

    try write("db", to: legacy.appendingPathComponent("library.sqlite"))

    Store.migrateFromLegacyDirectory(into: new, from: legacy)

    #expect(read(new.appendingPathComponent("library.sqlite")) == "db")
}
