import Foundation
import Testing

@testable import Image2PromptCore

// 移植正确性的真正判据不是"编译通过"，而是**能解码真实数据**。
// 这两份 fixture 是 core-ts 用真图跑出来的，两侧共用同一批数据——
// 哪个字段名映射错了、哪个枚举少了一个 case，这里立刻炸。

private let fixturesDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // 去掉文件名 → Tests/Image2PromptCoreTests
    .deletingLastPathComponent()  // → Tests
    .deletingLastPathComponent()  // → app
    .deletingLastPathComponent()  // → 仓库根
    .appendingPathComponent("core-ts/evals/fixtures")

private func loadFixture(_ name: String) throws -> StyleSpec {
    try StyleSpec.decode(contentsOf: fixturesDir.appendingPathComponent(name))
}

@Test("解码红色像素风新年海报")
func decodeRedPixelPoster() throws {
    let spec = try loadFixture("red-pixel-newyear-poster.stylespec.json")

    #expect(spec.schemaVersion == "0.1")
    #expect(spec.palette.isEmpty == false)
    #expect(spec.styleDna.isEmpty == false)

    // palette 只列主色（schema 上限 8 项），合计**不要求**等于 1——
    // 剩下的是不值得单列的杂色。真实契约是：不超过 1，且覆盖画面主体部分。
    let total = spec.palette.reduce(0) { $0 + $1.ratio }
    #expect(total <= 1.0, "色板占比之和 \(total) 超过 1")
    #expect(total >= 0.8, "色板只覆盖 \(total)，主色没抓全，色彩偏移的基准会失真")
}

@Test("解码白色高调秤产品图")
func decodeWhiteHighKeyHero() throws {
    let spec = try loadFixture("white-highkey-scale-hero.stylespec.json")

    #expect(spec.schemaVersion == "0.1")
    #expect(spec.styleDna.isEmpty == false)
    #expect(spec.confidence.overall > 0)
}

@Test("编码后能再解回来，不丢字段")
func roundTrip() throws {
    let original = try loadFixture("red-pixel-newyear-poster.stylespec.json")
    let restored = try StyleSpec.decode(from: original.encoded())
    #expect(original == restored)
}

@Test("内容层与风格层物理隔离：style_dna 不得含 content 的主体词")
func styleDnaHasNoContentLeakage() throws {
    for name in [
        "red-pixel-newyear-poster.stylespec.json",
        "white-highkey-scale-hero.stylespec.json",
    ] {
        let spec = try loadFixture(name)
        // 品牌标记是最硬的泄漏判据：出现在风格块里一定是错的
        for mark in spec.content.brandMarks where mark.count >= 2 {
            #expect(
                spec.styleDna.contains(mark) == false,
                "\(name) 的 style_dna 里出现了品牌标记「\(mark)」"
            )
        }
    }
}
