import Foundation
import Testing

@testable import FormlessCore

private func tempStore() throws -> Store {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("i2p-test-\(UUID().uuidString).sqlite")
    return try Store(url: url)
}

private let fixtures = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("core-ts/evals/fixtures")

private func sampleSpec() throws -> StyleSpec {
    try StyleSpec.decode(
        contentsOf: fixtures.appendingPathComponent("red-pixel-newyear-poster.stylespec.json"))
}

@Test("空库读出空列表")
@MainActor
func emptyStore() throws {
    let store = try tempStore()
    #expect(try store.loadAll().isEmpty)
    #expect(store.count == 0)
}

@Test("存进去再读回来，字段不丢")
@MainActor
func roundTripsItem() throws {
    let store = try tempStore()
    let item = QueueItem(imageURL: URL(fileURLWithPath: "/tmp/a.jpg"))
    item.spec = try sampleSpec()
    item.status = .done
    item.briefText = "做一张微信头图，主体换成血糖仪"
    item.brief = Brief(purpose: "wechat_cover", aspectRatio: "2.35:1", subject: "血糖仪")

    try store.upsert(item)

    let loaded = try #require(try store.loadAll().first)
    #expect(loaded.id == item.id)
    #expect(loaded.imageURL.path == "/tmp/a.jpg")
    #expect(loaded.status == .done)
    #expect(loaded.spec == item.spec)
    #expect(loaded.briefText == item.briefText)
    #expect(loaded.brief?.subject == "血糖仪")
    #expect(loaded.brief?.aspectRatio == "2.35:1")
}

@Test("失败原因也存下来")
@MainActor
func persistsFailureMessage() throws {
    let store = try tempStore()
    let item = QueueItem(imageURL: URL(fileURLWithPath: "/tmp/b.jpg"))
    item.status = .failed("agent 退出码 3：找不到图片")
    try store.upsert(item)

    let loaded = try #require(try store.loadAll().first)
    guard case .failed(let message) = loaded.status else {
        Issue.record("状态应为失败，实际 \(loaded.status)")
        return
    }
    #expect(message.contains("退出码 3"))
}

@Test("「分析中」会被存成「等待」")
@MainActor
func analyzingBecomesWaitingOnReload() throws {
    // 进程都没了，那次分析不可能跑完——重开该回到等待，
    // 而不是显示一个永远转不完的圈
    let store = try tempStore()
    let item = QueueItem(imageURL: URL(fileURLWithPath: "/tmp/c.jpg"))
    item.status = .analyzing
    try store.upsert(item)

    #expect(try store.loadAll().first?.status == .waiting)
}

@Test("同一路径重复写入只留一条，并更新内容")
@MainActor
func upsertDeduplicatesByPath() throws {
    let store = try tempStore()
    let url = URL(fileURLWithPath: "/tmp/same.jpg")

    let first = QueueItem(imageURL: url)
    first.briefText = "第一版"
    try store.upsert(first)

    let second = QueueItem(imageURL: url)
    second.briefText = "第二版"
    second.status = .done
    try store.upsert(second)

    let all = try store.loadAll()
    #expect(all.count == 1)
    #expect(all.first?.briefText == "第二版")
    #expect(all.first?.status == .done)
}

@Test("删除单条")
@MainActor
func deletesItem() throws {
    let store = try tempStore()
    let a = QueueItem(imageURL: URL(fileURLWithPath: "/tmp/a.jpg"))
    let b = QueueItem(imageURL: URL(fileURLWithPath: "/tmp/b.jpg"))
    try store.upsert(a)
    try store.upsert(b)

    try store.delete(id: a.id)
    let all = try store.loadAll()
    #expect(all.count == 1)
    #expect(all.first?.imageURL.lastPathComponent == "b.jpg")
}

@Test("按加入时间排序")
@MainActor
func ordersByAddedAt() throws {
    let store = try tempStore()
    let now = Date()
    for (i, name) in ["c", "a", "b"].enumerated() {
        try store.upsert(
            QueueItem(
                imageURL: URL(fileURLWithPath: "/tmp/\(name).jpg"),
                addedAt: now.addingTimeInterval(Double(3 - i))))
    }
    let names = try store.loadAll().map(\.imageURL.lastPathComponent)
    #expect(names == ["b.jpg", "a.jpg", "c.jpg"])
}

@Test("队列重启后恢复：拖入 → 分析完 → 重开还在")
@MainActor
func queueSurvivesRestart() async throws {
    let dbURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("i2p-restart-\(UUID().uuidString).sqlite")

    do {
        let queue = AnalysisQueue(
            provider: MockVisionProvider(delayRange: 0.01...0.02),
            store: try Store(url: dbURL))
        queue.enqueue([URL(fileURLWithPath: "/tmp/x.jpg"), URL(fileURLWithPath: "/tmp/y.jpg")])

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, !queue.items.allSatisfy({ $0.status.isTerminal }) {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(queue.doneCount == 2)
    }

    // 新开一个队列，模拟重启
    let reopened = AnalysisQueue(
        provider: MockVisionProvider(delayRange: 0.01...0.02),
        store: try Store(url: dbURL))
    #expect(reopened.items.count == 2)
    #expect(reopened.doneCount == 2)
    #expect(reopened.items.allSatisfy { $0.spec != nil }, "StyleSpec 没有被持久化")
}

@Test("重启后没跑完的条目会接着跑")
@MainActor
func resumesPendingAfterRestart() async throws {
    let dbURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("i2p-resume-\(UUID().uuidString).sqlite")

    // 先手工塞两条「等待」进库，模拟上次没跑完就退出
    let store = try Store(url: dbURL)
    for name in ["p.jpg", "q.jpg"] {
        try store.upsert(QueueItem(imageURL: URL(fileURLWithPath: "/tmp/\(name)")))
    }

    let queue = AnalysisQueue(
        provider: MockVisionProvider(delayRange: 0.01...0.03),
        store: try Store(url: dbURL))
    #expect(queue.items.count == 2)
    #expect(queue.pendingCount == 2)
    // 光是读回来还不够——不调 resumePending 它们会永远卡在等待
    #expect(queue.activeCount == 0)

    queue.autoAnalyze = true
    queue.resumePending()

    let deadline = Date().addingTimeInterval(5)
    while Date() < deadline, !queue.items.allSatisfy({ $0.status.isTerminal }) {
        try await Task.sleep(nanoseconds: 20_000_000)
    }
    #expect(queue.doneCount == 2)
}

@Test("关掉自动分析时，重启不会擅自开跑")
@MainActor
func doesNotResumeWhenAutoAnalyzeOff() async throws {
    let dbURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("i2p-noresume-\(UUID().uuidString).sqlite")
    let store = try Store(url: dbURL)
    try store.upsert(QueueItem(imageURL: URL(fileURLWithPath: "/tmp/r.jpg")))

    let queue = AnalysisQueue(
        provider: MockVisionProvider(delayRange: 0.01...0.03),
        store: try Store(url: dbURL))
    queue.autoAnalyze = false
    queue.resumePending()

    try await Task.sleep(nanoseconds: 150_000_000)
    #expect(queue.pendingCount == 1)
    #expect(queue.doneCount == 0)
}

@Test("没有 store 时纯内存运行，不报错")
@MainActor
func worksWithoutStore() async throws {
    let queue = AnalysisQueue(provider: MockVisionProvider(delayRange: 0.01...0.02))
    queue.enqueue([URL(fileURLWithPath: "/tmp/z.jpg")])
    #expect(queue.items.count == 1)
    #expect(queue.lastStoreError == nil)
}
