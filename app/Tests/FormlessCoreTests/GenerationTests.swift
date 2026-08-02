import Foundation
import Testing

@testable import FormlessCore

// MARK: - 画幅取向

@Test("画幅比例解析")
func parsesAspectRatio() {
    #expect(CodexImageProvider.parseRatio("3:4") == 0.75)
    #expect(CodexImageProvider.parseRatio("16:9") == 16.0 / 9.0)
    #expect(CodexImageProvider.parseRatio("1:1") == 1.0)
    // 中文冒号是中文输入法下最容易打出来的，必须吃得下
    #expect(CodexImageProvider.parseRatio("3：4") == 0.75)
}

@Test("解析不了就不猜")
func refusesToGuessRatio() {
    #expect(CodexImageProvider.parseRatio("竖版") == nil)
    #expect(CodexImageProvider.parseRatio("3:0") == nil)
    #expect(CodexImageProvider.parseRatio("") == nil)
}

@Test("画幅必须写进提示词本身")
func aspectGoesIntoThePrompt() {
    // 内置 image_gen 没有尺寸参数（那是 CLI fallback 专属），agent 拿到"要 3:4"
    // 也无处可传。提示词是唯一能到达生图模型的通道——实测不加这一句，
    // 要 3:4 会拿到 1254×1254 方图。
    let request = sampleRequest()
    let sent = CodexImageProvider.composePrompt(request)
    #expect(sent.hasPrefix(request.prompt), "编译器产出必须原样在前，只能往后追加")
    #expect(sent.contains("3:4"))
    #expect(sent.contains("竖构图"))

    #expect(CodexImageProvider.aspectClause("16:9")?.contains("横构图") == true)
    #expect(CodexImageProvider.aspectClause("1:1")?.contains("方构图") == true)
}

@Test("画幅解析不了就不往提示词里加东西")
func noAspectClauseWhenUnparseable() {
    let request = GenerationRequest(
        prompt: "一枚邮票", model: .gptImage, aspectRatio: "竖版",
        jobDirectory: URL(fileURLWithPath: "/tmp/x"))
    #expect(CodexImageProvider.composePrompt(request) == "一枚邮票")
    #expect(CodexImageProvider.aspectClause("竖版") == nil)
}

// MARK: - 指令

private func sampleRequest(prompt: String = "一枚邮票，纯平涂，正红底色") -> GenerationRequest {
    GenerationRequest(
        prompt: prompt,
        model: .gptImage,
        aspectRatio: "3:4",
        jobDirectory: URL(fileURLWithPath: "/tmp/formless-test-job")
    )
}

@Test("指令逐字带上提示词")
func instructionCarriesPromptVerbatim() {
    let prompt = "瑞士国际主义排版：主色 #FF2424 约占 74%，纯平涂，无渐变"
    let request = sampleRequest(prompt: prompt)
    let sent = CodexImageProvider.composePrompt(request)
    let text = CodexImageProvider.instruction(
        for: request, sentPrompt: sent,
        resultPNG: URL(fileURLWithPath: "/tmp/formless-test-job/result.png"))
    #expect(text.contains(prompt))
    #expect(text.contains(sent))
}

@Test("四条硬约束一条都不能少")
func instructionKeepsAllGuards() {
    // 每一条都对应 imagegen SKILL.md 里一个会让它跑偏的分支，
    // 少一条就会有一批图作废。
    let request = sampleRequest()
    let text = CodexImageProvider.instruction(
        for: request, sentPrompt: CodexImageProvider.composePrompt(request),
        resultPNG: URL(fileURLWithPath: "/tmp/formless-test-job/result.png"))

    #expect(text.hasPrefix("$imagegen"))
    #expect(text.contains("只调用一次"))
    #expect(text.contains("SVG"))  // 别用矢量代替位图
    #expect(text.contains("OPENAI_API_KEY"))  // 别转 CLI fallback
    #expect(text.contains("不要做任何缩放"))  // 别事后拉伸
    #expect(text.contains("逐字原样使用"))  // 别重写提示词
    #expect(text.contains("final_prompt"))  // 必须回传实际用的提示词
}

@Test("指令写死结果路径，不靠猜最新一张")
func instructionPinsResultPath() {
    // Codex 把图落在 ~/.codex/generated_images/<session-uuid>/，
    // 并发时去猜"最新的一张"一定串图。
    let png = URL(fileURLWithPath: "/tmp/formless-test-job/result.png")
    let request = sampleRequest()
    let text = CodexImageProvider.instruction(
        for: request, sentPrompt: CodexImageProvider.composePrompt(request), resultPNG: png)
    #expect(text.contains(png.path))
}

// MARK: - 结果契约

@Test("result schema 必须要求 final_prompt")
func schemaRequiresFinalPrompt() throws {
    let obj = try #require(
        try JSONSerialization.jsonObject(with: Data(CodexImageProvider.resultSchema.utf8))
            as? [String: Any])
    let required = try #require(obj["required"] as? [String])
    // 没有这个字段就无法判断提示词有没有被改写，整个实验失去有效性
    #expect(required.contains("final_prompt"))
    #expect(required.contains("tool_used"))
    #expect(required.contains("status"))
}

// MARK: - 实验有效性判据

private func record(prompt: String, finalPrompt: String?, tool: String? = "builtin_image_gen")
    -> GenerationStore.Record
{
    GenerationStore.Record(
        jobID: "j", createdAt: Date(), model: .gptImage, prompt: prompt,
        finalPrompt: finalPrompt, pixelWidth: 1024, pixelHeight: 1536, toolUsed: tool)
}

@Test("提示词逐字一致才算有效证据")
func verbatimJudgement() {
    let p = "一枚邮票，纯平涂"
    #expect(record(prompt: p, finalPrompt: p).promptIsVerbatim)
    // 哪怕只多一个句号也算被改写——规范化本身就是改写
    #expect(!record(prompt: p, finalPrompt: p + "。").promptIsVerbatim)
    #expect(!record(prompt: p, finalPrompt: "一枚邮票，纯平涂风格").promptIsVerbatim)
    // 没回传就当没有证据，不能默认通过
    #expect(!record(prompt: p, finalPrompt: nil).promptIsVerbatim)
}

@Test("认得出没走内置工具的情况")
func detectsNonBuiltinPath() {
    // 本机 skill 装得多时 Codex 会截断 skill 描述，触发不是必然
    #expect(record(prompt: "x", finalPrompt: "x").usedBuiltinTool)
    #expect(!record(prompt: "x", finalPrompt: "x", tool: "cli_fallback").usedBuiltinTool)
    #expect(!record(prompt: "x", finalPrompt: "x", tool: nil).usedBuiltinTool)
}

// MARK: - 任务目录

@Test("每次生成一个唯一目录")
func jobDirectoriesAreUnique() throws {
    let id = UUID()
    defer { try? FileManager.default.removeItem(at: GenerationStore.directory(for: id)) }

    let a = try GenerationStore.newJobDirectory(for: id)
    let b = try GenerationStore.newJobDirectory(for: id)
    #expect(a.jobID != b.jobID)
    #expect(a.url != b.url)
    #expect(FileManager.default.fileExists(atPath: a.url.path))
}

// MARK: - 实跑

/// 真的调一次 Codex 出图。**默认跳过**：它要花掉一次 Codex 生图额度、要联网、要跑 3~4 分钟，
/// 不该在每次 `swift test` 时都发生。
///
/// ```bash
/// FORMLESS_LIVE_GEN=1 swift test --filter liveGeneration
/// ```
@Test(
    "实跑一次生图（消耗 Codex 额度）",
    .enabled(if: ProcessInfo.processInfo.environment["FORMLESS_LIVE_GEN"] == "1"),
    .timeLimit(.minutes(15))
)
func liveGeneration() async throws {
    let provider = try #require(
        CodexImageProvider.isAvailable ? CodexImageProvider(timeout: 900) : nil,
        "本机没装 codex")

    let itemID = UUID()
    let job = try GenerationStore.newJobDirectory(for: itemID)
    let prompt = "一枚方形齿孔邮票居中，纯平涂无渐变，正红底色，米杏色与纯黑色块，直角硬边几何，复古像素风"

    let result = try await provider.generate(
        GenerationRequest(
            prompt: prompt, model: .gptImage, aspectRatio: "3:4", jobDirectory: job.url))

    // 三条断言对应冒烟测试里查出来的三个风险
    #expect(result.promptIsVerbatim, "提示词被改写了：\(result.finalPrompt ?? "nil")")
    #expect(result.toolUsed == "builtin_image_gen", "没走内置工具：\(result.toolUsed ?? "nil")")
    #expect(result.pixelWidth > 0 && result.pixelHeight > 0)
    #expect(FileManager.default.fileExists(atPath: result.imageURL.path))

    // 存一条记录再读回来，验证 GUI 走的那条落盘路径
    try GenerationStore.save(
        GenerationStore.Record(
            jobID: job.jobID, createdAt: Date(), model: .gptImage, prompt: result.sentPrompt,
            finalPrompt: result.finalPrompt, pixelWidth: result.pixelWidth,
            pixelHeight: result.pixelHeight, toolUsed: result.toolUsed,
            requestedAspect: "3:4"),
        in: job.url)
    let history = GenerationStore.history(for: itemID)
    #expect(history.count == 1)
    #expect(history.first?.record.promptIsVerbatim == true)

    let matched = history.first?.record.aspectMatches
    print("✓ 实跑成功：\(result.pixelSize)，画幅中没中 = \(matched.map(String.init(describing:)) ?? "未知")")
    print("  \(result.imageURL.path)")
}

@Test("没有 meta.json 的半截任务不算一条记录")
func skipsIncompleteJobs() throws {
    let id = UUID()
    defer { try? FileManager.default.removeItem(at: GenerationStore.directory(for: id)) }

    let job = try GenerationStore.newJobDirectory(for: id)
    // 只有图没有 meta：跑到一半退出的样子
    try Data("not a real png".utf8).write(to: job.url.appendingPathComponent("result.png"))
    #expect(GenerationStore.history(for: id).isEmpty)

    try GenerationStore.save(
        record(prompt: "p", finalPrompt: "p"), in: job.url)
    #expect(GenerationStore.history(for: id).count == 1)
}

// MARK: - 画幅判定

@Test("画幅中没中要判得出来")
func detectsAspectMismatch() {
    func rec(_ w: Int, _ h: Int, want: String?) -> GenerationStore.Record {
        GenerationStore.Record(
            jobID: "j", createdAt: Date(), model: .gptImage, prompt: "p", finalPrompt: "p",
            pixelWidth: w, pixelHeight: h, toolUsed: "builtin_image_gen", requestedAspect: want)
    }
    // 实测撞到过的那张：要 3:4 拿到方图
    #expect(rec(1254, 1254, want: "3:4").aspectMatches == false)
    #expect(rec(1200, 1600, want: "3:4").aspectMatches == true)
    // 1024×1536 是 2:3，离 3:4 差了 11%，超出 5% 容差
    #expect(rec(1024, 1536, want: "3:4").aspectMatches == false)
    #expect(rec(1024, 1536, want: "2:3").aspectMatches == true)
    // 没要求 / 解析不了就不下判断，不能默认算中
    #expect(rec(1254, 1254, want: nil).aspectMatches == nil)
    #expect(rec(1254, 1254, want: "竖版").aspectMatches == nil)
}
