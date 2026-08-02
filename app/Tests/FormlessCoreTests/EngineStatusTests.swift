import Foundation
import Testing

@testable import FormlessCore

// 这几句话决定用户要不要去买 API——写错了会让人白花钱，所以它们要能被测。
// 核心原则：**以实际能不能跑为准，不是以用户选了什么为准**。

@MainActor
private func withSettings(_ body: (Settings) -> Void) {
    let s = Settings.shared
    let saved = (s.providerID, s.customExecutable, s.apiKey)
    defer {
        s.providerID = saved.0
        s.customExecutable = saved.1
        s.apiKey = saved.2
    }
    body(s)
}

@Test("Mock 要明说结果是假的")
@MainActor
func mockStatusIsHonest() {
    withSettings { s in
        s.providerID = "mock"
        let status = s.visionStatus
        #expect(status.level == .degraded)
        #expect(status.isReal == false, "Mock 不算真的能识图")
        #expect(status.detail?.contains("与你拖进来的图无关") == true)
    }
}

@Test("装了的本地 agent 报就绪，并给出真实路径")
@MainActor
func readyAgentReportsPath() {
    withSettings { s in
        s.providerID = "custom"
        s.customExecutable = "/bin/echo"
        let status = s.visionStatus
        #expect(status.level == .ready)
        #expect(status.isReal)
        #expect(status.detail == "/bin/echo")
        #expect(status.channel.contains("不额外计费"), "要说清走的是订阅不是 API")
    }
}

@Test("找不到的 agent 报错，不假装能用")
@MainActor
func brokenAgentReportsError() {
    withSettings { s in
        s.providerID = "custom"
        s.customExecutable = "definitely-not-real-binary-xyz"
        let status = s.visionStatus
        #expect(status.level == .broken)
        #expect(status.isReal == false)
    }
}

@Test("选了 agent 但没填可执行文件，要说明实际仍走 Mock")
@MainActor
func emptyExecutableFallsBackHonestly() {
    withSettings { s in
        s.providerID = "custom"
        s.customExecutable = ""
        let status = s.visionStatus
        #expect(status.level == .degraded)
        #expect(status.isReal == false)
        #expect(status.detail?.contains("Mock") == true, "必须点明当前实际走的是 Mock")
    }
}

@Test("选了 API 但没填 key，同样要说明实际走 Mock")
@MainActor
func apiWithoutKeyIsHonest() {
    withSettings { s in
        s.providerID = "anthropic"
        s.apiKey = ""
        let status = s.visionStatus
        #expect(status.level == .degraded)
        #expect(status.detail?.contains("Mock") == true)
    }
}

@Test("生图能力与识图引擎无关")
@MainActor
func generationIsIndependentOfVisionEngine() {
    // 2026-08-02 起生图这条路通了（Codex 内置 image_gen），但它和识图是两条独立的路：
    // 生图取决于本机装没装 codex，跟这里选了 Mock 还是 Anthropic 没有关系。
    // 这一条写错，用户会以为"换个识图引擎就能出图"或"选了 Mock 就出不了图"。
    let expected = CodexImageProvider.isAvailable
    withSettings { s in
        for (provider, exe) in [("mock", ""), ("custom", "/bin/echo"), ("anthropic", "")] {
            s.providerID = provider
            s.customExecutable = exe
            #expect(
                s.generationStatus.isReal == expected,
                "\(provider) 的生图能力不该随识图引擎变化")
        }
    }
}

@Test("识图不可用时也不影响生图")
@MainActor
func brokenVisionStillAllowsGeneration() {
    // 识图引擎坏了（找不到可执行文件）不该连带把生图按钮也关掉
    withSettings { s in
        s.providerID = "custom"
        s.customExecutable = "/nonexistent/definitely-not-here"
        let status = s.visionStatus
        #expect(status.isReal == false)
        #expect(s.generationStatus.isReal == CodexImageProvider.isAvailable)
    }
}

@Test("清空本地库只删索引，条目归零")
@MainActor
func clearAllEmptiesQueue() async throws {
    let dbURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("i2p-clear-\(UUID().uuidString).sqlite")
    let queue = AnalysisQueue(
        provider: MockVisionProvider(delayRange: 0.01...0.02), store: try Store(url: dbURL))
    queue.enqueue([URL(fileURLWithPath: "/tmp/a.jpg"), URL(fileURLWithPath: "/tmp/b.jpg")])
    #expect(queue.items.count == 2)

    queue.clearAll()
    #expect(queue.items.isEmpty)
    // 重开也应该是空的
    let reopened = AnalysisQueue(
        provider: MockVisionProvider(delayRange: 0.01...0.02), store: try Store(url: dbURL))
    #expect(reopened.items.isEmpty)
}
