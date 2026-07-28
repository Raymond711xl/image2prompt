import Foundation
import Testing

@testable import Image2PromptCore

private let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

@Test("打包里的 fixture 与 core-ts 原件字节一致")
func bundledFixturesMatchCoreTS() throws {
    // app/Resources 里的是 core-ts/evals/fixtures 的镜像。两边任何一侧被改动而
    // 另一侧没跟上，Mock 就会用过期数据——这条测试专门盯这个漂移。
    for name in MockVisionProvider.fixtureNames {
        let origin = repoRoot
            .appendingPathComponent("core-ts/evals/fixtures/\(name).json")
        guard let bundled = Bundle.module.url(forResource: name, withExtension: "json") else {
            Issue.record("打包里缺 \(name).json")
            continue
        }
        #expect(
            try Data(contentsOf: origin) == (try Data(contentsOf: bundled)),
            "\(name).json 与 core-ts 原件不一致，镜像已漂移"
        )
    }
}

@Test("Mock 能产出合法 StyleSpec")
func mockReturnsValidSpec() async throws {
    let provider = MockVisionProvider(delayRange: 0.01...0.02)
    let spec = try await provider.analyze(imageURL: URL(fileURLWithPath: "/tmp/foo.jpg"))
    #expect(spec.schemaVersion == "0.1")
    #expect(spec.styleDna.isEmpty == false)
}

@Test("同一张图重复分析结果稳定")
func sameImageYieldsSameSpec() async throws {
    // 重试时换一份 StyleSpec 会看起来像 bug，必须稳定
    let provider = MockVisionProvider(delayRange: 0.01...0.02)
    let url = URL(fileURLWithPath: "/tmp/poster.png")
    let a = try await provider.analyze(imageURL: url)
    let b = try await provider.analyze(imageURL: url)
    #expect(a == b)
}

@Test("失败率 1 时必定抛错，用于验证失败态")
func failureRateThrows() async throws {
    let provider = MockVisionProvider(delayRange: 0.01...0.02, failureRate: 1)
    await #expect(throws: VisionError.self) {
        _ = try await provider.analyze(imageURL: URL(fileURLWithPath: "/tmp/foo.jpg"))
    }
}
