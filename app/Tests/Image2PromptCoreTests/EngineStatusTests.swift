import Foundation
import Testing

@testable import Image2PromptCore

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
        let status = s.engineStatus
        #expect(status.level == .degraded)
        #expect(status.canAnalyze == false, "Mock 不算真的能识图")
        #expect(status.detail?.contains("与你拖进来的图无关") == true)
    }
}

@Test("装了的本地 agent 报就绪，并给出真实路径")
@MainActor
func readyAgentReportsPath() {
    withSettings { s in
        s.providerID = "custom"
        s.customExecutable = "/bin/echo"
        let status = s.engineStatus
        #expect(status.level == .ready)
        #expect(status.canAnalyze)
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
        let status = s.engineStatus
        #expect(status.level == .broken)
        #expect(status.canAnalyze == false)
    }
}

@Test("选了 agent 但没填可执行文件，要说明实际仍走 Mock")
@MainActor
func emptyExecutableFallsBackHonestly() {
    withSettings { s in
        s.providerID = "custom"
        s.customExecutable = ""
        let status = s.engineStatus
        #expect(status.level == .degraded)
        #expect(status.canAnalyze == false)
        #expect(status.detail?.contains("Mock") == true, "必须点明当前实际走的是 Mock")
    }
}

@Test("选了 API 但没填 key，同样要说明实际走 Mock")
@MainActor
func apiWithoutKeyIsHonest() {
    withSettings { s in
        s.providerID = "anthropic"
        s.apiKey = ""
        let status = s.engineStatus
        #expect(status.level == .degraded)
        #expect(status.detail?.contains("Mock") == true)
    }
}

@Test("任何引擎都不声称能生图")
@MainActor
func nothingClaimsGeneration() {
    // agent 和视觉 API 都只能看图不能画图。这一条写错，用户会以为填了 key 就能出图。
    withSettings { s in
        for (provider, exe) in [("mock", ""), ("custom", "/bin/echo"), ("anthropic", "")] {
            s.providerID = provider
            s.customExecutable = exe
            #expect(s.engineStatus.canGenerate == false, "\(provider) 不该声称能生图")
        }
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
