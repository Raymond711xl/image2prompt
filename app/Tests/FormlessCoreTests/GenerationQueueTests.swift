import Foundation
import Testing

@testable import FormlessCore

// MARK: - 进度推算

@Test("进度条永远不走到满格")
func fractionNeverCompletes() {
    // 跑到预期时长的两倍，条子仍然封顶在 92%——
    // 走满了却还没结束，进度条就变成了骗人的东西
    #expect(Pace.fraction(elapsed: 420, expected: 210) == 0.92)
    #expect(Pace.fraction(elapsed: 100_000, expected: 210) == 0.92)
}

@Test("进度条起步不是 0，也不超过封顶")
func fractionBounds() {
    // 刚开跑就给一点点，否则用户会以为没启动
    #expect(Pace.fraction(elapsed: 0, expected: 210) == 0.02)
    #expect(Pace.fraction(elapsed: 105, expected: 210) == 0.5)
    #expect(Pace.fraction(elapsed: 10, expected: 0) == 0)
}

@Test("用时显示成分:秒")
func clockFormat() {
    #expect(Pace.clock(0) == "0:00")
    #expect(Pace.clock(9) == "0:09")
    #expect(Pace.clock(133) == "2:13")
    #expect(Pace.clock(3661) == "61:01")
    #expect(Pace.clock(-5) == "0:00")
}

// MARK: - 生成队列

/// 假生图引擎：不真的跑 agent，只按要求成功或失败。
/// 成功时在任务目录里放一个占位 result.png——`history` 靠它判断这次任务算不算数。
private struct StubGenerationProvider: GenerationProvider {
    let id = "stub"
    let displayName = "测试用"
    var shouldFail = false
    var delay: Duration = .milliseconds(10)

    func generate(_ request: GenerationRequest) async throws -> GenerationResult {
        try? await Task.sleep(for: delay)
        if shouldFail { throw GenerationError.reportedFailure("测试用失败") }
        let png = request.jobDirectory.appendingPathComponent("result.png")
        try Data("fake".utf8).write(to: png)
        return GenerationResult(
            imageURL: png,
            sentPrompt: request.prompt,
            finalPrompt: request.prompt,
            pixelWidth: 1024,
            pixelHeight: 1536,
            toolUsed: "builtin_image_gen"
        )
    }
}

/// 每个用例一个独立的临时根目录，跑完就删。
/// 显式传进队列而不是设全局开关——测试是并行跑的，全局状态会互相踩。
private func withTempRoot(_ body: (URL) async throws -> Void) async rethrows {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("formless-gen-test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    try await body(root)
}

@MainActor
private func waitUntilIdle(_ queue: GenerationQueue, timeout: Double = 5) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if !queue.isBusy { return }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    Issue.record("生成队列在 \(timeout)s 内没有回到空闲")
}

@Test("生成成功：状态回到空闲，历史里多一条，完成回调报成功")
@MainActor
func generateSuccess() async throws {
    try await withTempRoot { root in
        let queue = GenerationQueue(provider: StubGenerationProvider(), storeRoot: root)
        let itemID = UUID()
        var finished: [(UUID, Bool)] = []
        queue.onFinished = { finished.append(($0, $1)) }

        queue.generate(itemID: itemID, model: .jimeng, prompt: "一只猫", aspectRatio: "3:4")
        #expect(queue.state(for: itemID).isRunning)
        #expect(queue.isBusy)

        try await waitUntilIdle(queue)

        #expect(queue.state(for: itemID) == .idle)
        #expect(queue.completionTick == 1)
        #expect(finished.count == 1)
        #expect(finished.first?.1 == true)
        #expect(GenerationStore.history(for: itemID, root: root).count == 1)
    }
}

@Test("生成失败：状态留下原因，回调报失败")
@MainActor
func generateFailure() async throws {
    try await withTempRoot { root in
        let queue = GenerationQueue(
            provider: StubGenerationProvider(shouldFail: true), storeRoot: root)
        let itemID = UUID()
        var finished: [(UUID, Bool)] = []
        queue.onFinished = { finished.append(($0, $1)) }

        queue.generate(itemID: itemID, model: .jimeng, prompt: "一只猫", aspectRatio: "3:4")
        try await waitUntilIdle(queue)

        #expect(finished.first?.1 == false)
        if case .failed(let message) = queue.state(for: itemID) {
            #expect(message.contains("测试用失败"))
        } else {
            Issue.record("失败后应该留下 .failed 状态，实际是 \(queue.state(for: itemID))")
        }
        // 失败不该留下半条历史：没有 result.png 的任务目录不算一次生成
        #expect(GenerationStore.history(for: itemID, root: root).isEmpty)
    }
}

@Test("一次只跑一个：忙的时候再点不会插进来第二个")
@MainActor
func singleFlight() async throws {
    try await withTempRoot { root in
        let queue = GenerationQueue(
            provider: StubGenerationProvider(delay: .milliseconds(200)), storeRoot: root)
        let first = UUID()
        let second = UUID()

        queue.generate(itemID: first, model: .jimeng, prompt: "一只猫", aspectRatio: "3:4")
        queue.generate(itemID: second, model: .jimeng, prompt: "一条狗", aspectRatio: "3:4")

        #expect(queue.state(for: first).isRunning)
        #expect(queue.state(for: second) == .idle)
        #expect(queue.runningItemID == first)

        try await waitUntilIdle(queue)
        #expect(queue.completionTick == 1)
    }
}

@Test("取消：状态写成已取消，且不响提示音")
@MainActor
func cancelDoesNotRing() async throws {
    try await withTempRoot { root in
        let queue = GenerationQueue(
            provider: StubGenerationProvider(delay: .milliseconds(100)), storeRoot: root)
        let itemID = UUID()
        var finished: [(UUID, Bool)] = []
        queue.onFinished = { finished.append(($0, $1)) }

        queue.generate(itemID: itemID, model: .jimeng, prompt: "一只猫", aspectRatio: "3:4")
        queue.cancel()
        try await waitUntilIdle(queue)

        #expect(queue.state(for: itemID) == .failed("已取消"))
        // 人就在跟前按的取消，不该再响一声告诉他
        #expect(finished.isEmpty)
        #expect(queue.completionTick == 0)

        // 取消完还能再起一个
        queue.generate(itemID: itemID, model: .jimeng, prompt: "一只猫", aspectRatio: "3:4")
        #expect(queue.state(for: itemID).isRunning)
        try await waitUntilIdle(queue)
        #expect(queue.completionTick == 1)
    }
}

@Test("没有引擎时点了也不动")
@MainActor
func noProviderDoesNothing() async throws {
    let queue = GenerationQueue(provider: nil)
    let itemID = UUID()
    queue.generate(itemID: itemID, model: .jimeng, prompt: "一只猫", aspectRatio: "3:4")

    #expect(queue.isAvailable == false)
    #expect(queue.state(for: itemID) == .idle)
    #expect(queue.isBusy == false)
}

@Test("移出队列后不再留着它的状态")
@MainActor
func forgetClearsState() async throws {
    try await withTempRoot { root in
        let queue = GenerationQueue(
            provider: StubGenerationProvider(shouldFail: true), storeRoot: root)
        let itemID = UUID()
        queue.generate(itemID: itemID, model: .jimeng, prompt: "一只猫", aspectRatio: "3:4")
        try await waitUntilIdle(queue)

        queue.forget(itemID: itemID)
        #expect(queue.state(for: itemID) == .idle)
    }
}
