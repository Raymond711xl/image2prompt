import Foundation
import ImageIO

/// 用本机 Codex CLI 的内置 `image_gen` 工具生图。
///
/// 2026-08-02 实测跑通，完整结论见 `docs/codex-imagegen.md`。要点：
///
/// - Codex CLI 0.144.1 起 `image_generation` 为 stable，自带
///   `~/.codex/skills/.system/imagegen`，内置工具**走 Codex 登录额度，
///   不需要 `OPENAI_API_KEY`**——识图和生图两头都能压到订阅成本内。
/// - 沙盒 `workspace-write` 下，从 `~/.codex/generated_images` 读、往 `-C` 目录写
///   直接可行，不需要 `--add-dir`。
/// - **内置模式控制不了精确画幅。** 尺寸参数是 CLI fallback 专属（那条要 API key）。
///   实测里 agent 会自作主张用 ffmpeg 把 1024×1536 拉成要求的 1200×1600——
///   非等比拉伸，横向拉宽 12.5%。画幅是我们要验证的硬字段，被事后拉伸就全废了，
///   所以指令里明确禁止任何缩放裁切，尺寸以实测为准。
public struct CodexImageProvider: GenerationProvider {
    public let id = "codex-imagegen"
    public let displayName = "Codex 内置 image_gen"

    /// 实测单张约 3~4 分钟，比识图（约 2.5 分钟）长。**别复用识图的超时值。**
    public let timeout: TimeInterval
    public let executable: String

    public init(timeout: TimeInterval = 900, executable: String = "codex") {
        self.timeout = timeout
        self.executable = executable
    }

    public static var isAvailable: Bool {
        (try? AgentRunner.resolveExecutable("codex")) != nil
    }

    public func generate(_ request: GenerationRequest) async throws -> GenerationResult {
        let fm = FileManager.default
        try fm.createDirectory(at: request.jobDirectory, withIntermediateDirectories: true)

        let resultPNG = request.jobDirectory.appendingPathComponent("result.png")
        let resultJSON = request.jobDirectory.appendingPathComponent("result.json")
        let schema = request.jobDirectory.appendingPathComponent("result.schema.json")
        let instructionURL = request.jobDirectory.appendingPathComponent("instruction.txt")

        // 重跑同一个任务目录时先清掉上一次的产物，否则失败了也会读到旧图
        for url in [resultPNG, resultJSON] where fm.fileExists(atPath: url.path) {
            try? fm.removeItem(at: url)
        }

        try Data(Self.resultSchema.utf8).write(to: schema)
        let sentPrompt = Self.composePrompt(request)
        let instruction = Self.instruction(
            for: request, sentPrompt: sentPrompt, resultPNG: resultPNG)
        try Data(instruction.utf8).write(to: instructionURL)

        let arguments = [
            "exec",
            "--ephemeral",
            "--skip-git-repo-check",
            "--sandbox", "workspace-write",
            "-C", request.jobDirectory.path,
            "--output-schema", schema.path,
            "-o", resultJSON.path,
            "-",
        ]

        do {
            _ = try await AgentRunner.run(
                executable: executable,
                arguments: arguments,
                stdin: instruction,
                timeout: timeout,
                currentDirectory: request.jobDirectory
            )
        } catch let error as AgentRunner.AgentError {
            throw GenerationError.agentFailed(error.errorDescription ?? "\(error)")
        }

        if Task.isCancelled { throw GenerationError.cancelled }

        // 只读 `-o` 指定的文件，**绝不解析 stdout**：实测 Codex 会先吐一条
        // 半成品 JSON（image_path 为 null、final_prompt 写的是"我将要…"），
        // 解析 stdout 就会拿到那一条。
        guard let data = try? Data(contentsOf: resultJSON) else {
            throw GenerationError.noResult("没有生成 \(resultJSON.lastPathComponent)")
        }
        let report: Report
        do {
            report = try JSONDecoder().decode(Report.self, from: data)
        } catch {
            throw GenerationError.noResult("result.json 解不开：\(error.localizedDescription)")
        }

        if report.status != "success" {
            throw GenerationError.reportedFailure(report.error ?? "agent 报告 status=\(report.status)")
        }
        guard fm.fileExists(atPath: resultPNG.path) else {
            throw GenerationError.noResult("agent 报告成功，但 \(resultPNG.lastPathComponent) 不存在")
        }
        guard let size = Self.pixelSize(of: resultPNG) else {
            throw GenerationError.undecodableImage(resultPNG)
        }

        return GenerationResult(
            imageURL: resultPNG,
            sentPrompt: sentPrompt,
            finalPrompt: report.finalPrompt,
            pixelWidth: size.width,
            pixelHeight: size.height,
            toolUsed: report.toolUsed
        )
    }

    // MARK: - 画幅

    /// 实际发出去的提示词 = 编译器产出 + 一句画幅。
    ///
    /// 画幅必须写进**提示词本身**，这是唯一能到达生图模型的通道：内置 `image_gen`
    /// 没有尺寸参数（那是 CLI fallback 专属），agent 拿到"要 3:4"也无处可传，
    /// 而我们又禁止了它事后拉伸。实测不加这一句，要 3:4 会得到 1254×1254 方图。
    ///
    /// 这仍然是**软约束**——模型可能不听。所以产出尺寸一律以实测为准，
    /// 不采信任何一方的自述。
    public static func composePrompt(_ request: GenerationRequest) -> String {
        guard let clause = aspectClause(request.aspectRatio) else { return request.prompt }
        return request.prompt + "。" + clause
    }

    static func aspectClause(_ aspectRatio: String) -> String? {
        guard let ratio = parseRatio(aspectRatio) else { return nil }
        let orientation = ratio < 0.95 ? "竖构图" : (ratio > 1.05 ? "横构图" : "方构图")
        return "画幅比例严格为 \(aspectRatio)（\(orientation)），整幅图按这个比例出图，不要方图、不要留白补边"
    }

    // MARK: - 结果契约

    private struct Report: Decodable {
        let status: String
        let imagePath: String?
        let finalPrompt: String?
        let size: String?
        let toolUsed: String?
        let error: String?

        enum CodingKeys: String, CodingKey {
            case status
            case imagePath = "image_path"
            case finalPrompt = "final_prompt"
            case size
            case toolUsed = "tool_used"
            case error
        }
    }

    /// `final_prompt` 是这份 schema 存在的理由——没有它就没法判断提示词有没有被改写。
    static let resultSchema = """
        {
          "type": "object",
          "additionalProperties": false,
          "required": ["status", "image_path", "final_prompt", "size", "tool_used", "error"],
          "properties": {
            "status": { "type": "string", "enum": ["success", "failed"] },
            "image_path": { "type": ["string", "null"] },
            "final_prompt": {
              "type": ["string", "null"],
              "description": "实际传给 image_gen 工具的完整提示词字符串，逐字，不要摘要"
            },
            "size": { "type": ["string", "null"], "description": "图片真实像素尺寸，如 1024x1536" },
            "tool_used": {
              "type": ["string", "null"],
              "description": "实际使用的生图路径：builtin_image_gen / cli_fallback / 其他"
            },
            "error": { "type": ["string", "null"] }
          }
        }
        """

    // MARK: - 指令

    /// 四条硬约束一条都不能少，来源是 imagegen SKILL.md 自己的行为：
    /// 它有 `Prompt augmentation` 一节会重写提示词、有 `When not to use` 分支会把
    /// 海报类劝去用 SVG/HTML/CSS、还有一条转 `scripts/image_gen.py` 的 fallback
    /// （**那条要 API key**）。不写死就会各自跑偏。
    static func instruction(for request: GenerationRequest, sentPrompt: String, resultPNG: URL)
        -> String
    {
        """
        $imagegen

        只使用内置 image_gen 工具生成一张图片，只调用一次。

        硬性约束，逐条遵守：
        1. 只用内置 image_gen，不要用 SVG / HTML / CSS / canvas 代替。
        2. 不要切换到 CLI fallback（scripts/image_gen.py），不要使用 OPENAI_API_KEY。
        3. 生成后不要做任何缩放、拉伸、裁切或重新编码，原样复制文件。尺寸不符合预期也不要修，如实回报。
        4. 下面这段提示词是外部编译器已经编译完成的最终提示词。逐字原样使用，不要重写、\
        不要规范化、不要结构化、不要增删任何内容，不要重新分析，不要改变主体、构图、颜色、比例和禁止项。\
        画幅要求已经写在提示词里，不要另外传尺寸参数，也不要事后调整尺寸。

        提示词开始
        \(sentPrompt)
        提示词结束

        生成完成后，把选定的那张图片原样复制到这个绝对路径（覆盖即可）：
        \(resultPNG.path)

        最后只返回 JSON。final_prompt 字段必须填你实际传给 image_gen 工具的那段完整字符串，\
        逐字复制，不要摘要、不要省略。size 字段填图片的真实像素尺寸。
        """
    }

    /// "3:4" → 0.75。解析不了返回 nil，不猜。
    static func parseRatio(_ text: String) -> Double? {
        let parts = text.split(whereSeparator: { $0 == ":" || $0 == "：" || $0 == "/" })
        guard parts.count == 2,
            let w = Double(parts[0].trimmingCharacters(in: .whitespaces)),
            let h = Double(parts[1].trimmingCharacters(in: .whitespaces)),
            h > 0
        else { return nil }
        return w / h
    }

    /// 自己量，不采信 agent 的自述。
    static func pixelSize(of url: URL) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = props[kCGImagePropertyPixelWidth] as? Int,
            let height = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return (width, height)
    }
}
