import Foundation
import Testing

@testable import Image2PromptCore

private func urls(_ names: String...) -> [URL] {
    names.map { URL(fileURLWithPath: "/tmp/\($0)") }
}

/// 等到队列里所有条目都走到终态，或超时
@MainActor
private func waitUntilSettled(_ queue: AnalysisQueue, timeout: Double = 5) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if queue.items.allSatisfy({ $0.status.isTerminal }) { return }
        try await Task.sleep(nanoseconds: 20_000_000)
    }
    Issue.record("队列在 \(timeout)s 内没有全部到终态")
}

@Test("自动分析开启时，入队即开跑并全部完成")
@MainActor
func autoAnalyzeRunsEverything() async throws {
    let queue = AnalysisQueue(provider: MockVisionProvider(delayRange: 0.01...0.03))
    queue.enqueue(urls("a.jpg", "b.jpg", "c.jpg"))

    #expect(queue.items.count == 3)
    try await waitUntilSettled(queue)

    #expect(queue.doneCount == 3)
    #expect(queue.items.allSatisfy { $0.spec != nil })
}

@Test("关掉自动分析后只入队不开跑")
@MainActor
func manualModeDoesNotStart() async throws {
    let queue = AnalysisQueue(provider: MockVisionProvider(delayRange: 0.01...0.03))
    queue.autoAnalyze = false
    queue.enqueue(urls("a.jpg", "b.jpg"))

    try await Task.sleep(nanoseconds: 100_000_000)
    #expect(queue.items.allSatisfy { $0.status == .waiting })
    #expect(queue.activeCount == 0)

    queue.startPending()
    try await waitUntilSettled(queue)
    #expect(queue.doneCount == 2)
}

@Test("并发不超过上限")
@MainActor
func respectsConcurrencyLimit() async throws {
    let queue = AnalysisQueue(provider: MockVisionProvider(delayRange: 0.15...0.2))
    queue.maxConcurrent = 2
    queue.enqueue(urls("a.jpg", "b.jpg", "c.jpg", "d.jpg", "e.jpg"))

    // 采样几次，任何时刻在飞的都不能超过 2
    for _ in 0..<8 {
        #expect(queue.activeCount <= 2, "同时在飞 \(queue.activeCount) 个，超过上限 2")
        try await Task.sleep(nanoseconds: 30_000_000)
    }
    try await waitUntilSettled(queue)
    #expect(queue.doneCount == 5)
}

@Test("暂停后不再启动新任务，恢复后继续")
@MainActor
func pauseStopsNewWork() async throws {
    let queue = AnalysisQueue(provider: MockVisionProvider(delayRange: 0.05...0.08))
    queue.maxConcurrent = 1
    queue.enqueue(urls("a.jpg", "b.jpg", "c.jpg"))

    queue.pause()
    try await Task.sleep(nanoseconds: 250_000_000)

    // 暂停时在飞的那个会跑完，但后面的必须还在等
    #expect(queue.pendingCount > 0, "暂停后仍在启动新任务")

    queue.resume()
    try await waitUntilSettled(queue)
    #expect(queue.doneCount == 3)
}

@Test("失败的条目可以重试成功")
@MainActor
func retryRecoversFailure() async throws {
    let queue = AnalysisQueue(provider: MockVisionProvider(delayRange: 0.01...0.02, failureRate: 1))
    queue.enqueue(urls("a.jpg"))
    try await waitUntilSettled(queue)

    let item = try #require(queue.items.first)
    guard case .failed = item.status else {
        Issue.record("应该失败，实际是 \(item.status)")
        return
    }

    // 换成不会失败的引擎再重试
    queue.setProvider(MockVisionProvider(delayRange: 0.01...0.02))
    queue.retry(item)
    try await waitUntilSettled(queue)

    #expect(item.status == .done)
    #expect(item.spec != nil)
}

@Test("重复拖入同一张图不产生重复条目")
@MainActor
func deduplicatesSameFile() async throws {
    let queue = AnalysisQueue(provider: MockVisionProvider(delayRange: 0.01...0.02))
    queue.enqueue(urls("a.jpg", "b.jpg"))
    queue.enqueue(urls("a.jpg", "c.jpg"))

    #expect(queue.items.count == 3)
    try await waitUntilSettled(queue)
}

@Test("清除已完成只留下未完成的")
@MainActor
func clearCompletedKeepsRest() async throws {
    let queue = AnalysisQueue(provider: MockVisionProvider(delayRange: 0.01...0.02))
    queue.enqueue(urls("a.jpg", "b.jpg"))
    try await waitUntilSettled(queue)

    queue.autoAnalyze = false
    queue.enqueue(urls("c.jpg"))
    queue.clearCompleted()

    #expect(queue.items.count == 1)
    #expect(queue.items.first?.fileName == "c.jpg")
}
