import Foundation

/// 假的识图引擎：返回两份真图跑出来的 StyleSpec，带可控延迟和可控失败。
///
/// 这不是一次性的临时代码。它是 VisionProvider 的一个正式实现，和 AnthropicProvider 平级，
/// 长期留下来当测试替身——没有它，队列的四个状态、失败重试、并发控制都没法在不烧钱的
/// 前提下验证。延迟是刻意的：瞬间返回的 mock 会让队列 UX 无法被真实感受。
public struct MockVisionProvider: VisionProvider {
    public let id = "mock"
    public let displayName = "Mock（假数据，不联网）"
    public let requiresAPIKey = false

    /// 每张图的模拟耗时区间，秒
    public var delayRange: ClosedRange<Double>
    /// 失败概率 0...1。用来验证失败态和重试按钮。
    public var failureRate: Double

    public init(delayRange: ClosedRange<Double> = 1.2...2.8, failureRate: Double = 0) {
        self.delayRange = delayRange
        self.failureRate = failureRate
    }

    /// 内置的假数据。按图片文件名的哈希稳定挑选——同一张图每次analyze结果一致，
    /// 否则重试会换一份 StyleSpec，看起来像 bug。
    public static let fixtureNames = [
        "red-pixel-newyear-poster.stylespec",
        "white-highkey-scale-hero.stylespec",
    ]

    public func analyze(imageURL: URL) async throws -> StyleSpec {
        let delay = Double.random(in: delayRange)
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

        if Task.isCancelled { throw VisionError.cancelled }

        if failureRate > 0, Double.random(in: 0...1) < failureRate {
            throw VisionError.transport("mock 模拟的网络失败")
        }

        return try Self.fixture(for: imageURL)
    }

    /// 按文件名稳定选一份 fixture
    public static func fixture(for imageURL: URL) throws -> StyleSpec {
        let hash = abs(imageURL.lastPathComponent.hashValue)
        let name = fixtureNames[hash % fixtureNames.count]
        return try loadFixture(named: name)
    }

    public static func loadFixture(named name: String) throws -> StyleSpec {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            throw VisionError.malformedResponse("打包里找不到 fixture：\(name).json")
        }
        return try StyleSpec.decode(contentsOf: url)
    }
}
