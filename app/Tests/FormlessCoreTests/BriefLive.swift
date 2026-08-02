import Foundation
import Testing
@testable import FormlessCore

/// 真的调一次本地 agent 解析。**默认跳过**（要跑约 30 秒）：
///
/// ```bash
/// FORMLESS_LIVE_BRIEF=1 swift test --filter liveBriefParse
/// ```
///
/// 守的是这次改造的核心承诺：**用户写的每一条都要有归宿**。
/// 正则解析在这段话上漏掉天安门、齿孔、怀旧、右下角留白；AI 解析一条不漏。
@Test(
  "实跑：AI 解析吃全率",
  .enabled(if: ProcessInfo.processInfo.environment["FORMLESS_LIVE_BRIEF"] == "1"),
  .timeLimit(.minutes(10)))
func liveBriefParse() async throws {
    let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    let spec = try StyleSpec.decode(contentsOf: repoRoot.appendingPathComponent(
        "core-ts/evals/fixtures/red-pixel-newyear-poster.stylespec.json"))
    let text = """
    用这个风格做一张小红书封面，主体换成一枚中国邮政的老邮票，票面是天安门，\
    要有齿孔边缘，整体偏怀旧一点，别太亮。标题「见字如面」放在下方，\
    右下角要留一块空白给二维码。不要人物，不要现代元素。
    """

    let parser = ModelBriefParser(preset: {
        var p = AgentPreset.claudeCode; p.timeout = 300; return p
    }())
    let brief = try await parser.parse(text: text, spec: spec)

    print("\n===== AI 解析 =====")
    print("subject       : \(brief.subject)")
    print("subjectDetail : \(brief.subjectDetail ?? "nil")")
    print("scene         : \(brief.scene ?? "nil")")
    print("copy.title    : \(brief.copy?.title ?? "nil")")
    print("copySafeArea  : \(brief.copySafeArea ?? "nil")")
    print("mustAvoid     : \(brief.mustAvoid ?? [])")
    print("aspectRatio   : \(brief.aspectRatio)")

    let prompt = try GPTImageAdapter.compile(spec, brief).text2img ?? ""
    print("\n===== 关键信息是否进了提示词 =====")
    var missed: [String] = []
    for k in ["天安门", "齿孔", "怀旧", "邮票"] {
        let hit = prompt.contains(k)
        print("\(hit ? "✅" : "❌")  \(k)")
        if !hit { missed.append(k) }
    }
    print("\n提示词：\n\(prompt)")
    #expect(missed.isEmpty, "仍然漏了：\(missed)")
}
