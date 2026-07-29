import Foundation
import Testing

@testable import FormlessCore

private let fixtures = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("core-ts/evals/fixtures")

private func spec() throws -> StyleSpec {
    try StyleSpec.decode(
        contentsOf: fixtures.appendingPathComponent("red-pixel-newyear-poster.stylespec.json"))
}

private func parse(_ text: String) throws -> Brief {
    HeuristicBriefParser.parseSync(text: text, spec: try spec())
}

@Test("识别用途：微信头图")
func detectsWechatCover() throws {
    let b = try parse("用这个风格做一张微信公众号头图，主体换成血糖仪")
    #expect(b.purpose == "wechat_cover")
    // 用途的常规比例优先于参考图比例——参考图是竖版海报，头图该是宽幅
    #expect(b.aspectRatio == "2.35:1")
}

@Test("识别用途：小红书封面")
func detectsXHS() throws {
    #expect(try parse("做个小红书封面").purpose == "xhs_cover")
}

@Test("显式比例优先于用途默认值")
func explicitRatioWins() throws {
    #expect(try parse("做张海报，16:9").aspectRatio == "16:9")
    #expect(try parse("做张海报，比例 9：16").aspectRatio == "9:16")
}

@Test("竖版横版方形能识别")
func detectsOrientation() throws {
    #expect(try parse("来个横版的背景图").aspectRatio == "16:9")
    #expect(try parse("正方形的海报").aspectRatio == "1:1")
}

@Test("提取主体")
func extractsSubject() throws {
    #expect(try parse("主体换成一台血糖仪").subject == "一台血糖仪")
    #expect(try parse("我想做一张登山靴的海报").subject == "登山靴的海报")
    #expect(try parse("换成德邦物流的展位").subject == "德邦物流的展位")
}

@Test("提取引号里的文案")
func extractsCopy() throws {
    let b = try parse("海报，标题「焕新一夏」，副标题「限时特惠」")
    #expect(b.copy?.title == "焕新一夏")
    #expect(b.copy?.subtitle == "限时特惠")
}

@Test("默认不让模型画字，除非明确要求")
func textInImageDefaultsOff() throws {
    // 文字正确性和排版后期叠图层更可控，这是 knowledge 里的既定判断
    #expect(try parse("海报，标题「焕新一夏」").renderTextInImage == false)
    #expect(try parse("海报，标题「焕新一夏」，把字直接生成文字画上去").renderTextInImage == true)
}

@Test("提取禁止项和保留项")
func extractsAvoidAndKeep() throws {
    let b = try parse("做张海报，不要人物，避免渐变，保留原来的红色")
    #expect(b.mustAvoid?.contains("人物") == true)
    #expect(b.mustAvoid?.contains("渐变") == true)
    #expect(b.mustKeep?.contains("原来的红色") == true)
}

@Test("解析结果能直接编译出提示词")
func parsedBriefCompiles() throws {
    let s = try spec()
    let b = try parse("用这个风格做一张微信公众号头图，主体换成一台血糖仪，不要人物")
    let prompt = try Compiler.compile(s, b, model: .jimeng)

    let text = try #require(prompt.text2img)
    #expect(text.contains("一台血糖仪"))
    // 禁止项"人物"应被转成正向表述，而不是写一句模型听不懂的否定
    #expect(text.contains("画面仅有产品与环境"))
    #expect(text.contains("不要") == false, "提示词里不该出现否定词")
}

@Test("原始输入完整保留在 notes 里")
func keepsRawText() throws {
    let raw = "随便写的一大段话，包含很多信息"
    #expect(try parse(raw).notes == raw)
}
