import Foundation

/// 用本地 agent 把一段自由描述读成完整 Brief。
///
/// 为什么必须换掉正则解析：`HeuristicBriefParser` 只认「换成 X」「「引号」」「不要 Y」
/// 这几个句式，别的全当噪声。实测一段 94 字的描述——
///
/// > 用这个风格做一张小红书封面，主体换成一枚中国邮政的老邮票，票面是天安门，
/// > 要有齿孔边缘，整体偏怀旧一点，别太亮。标题「见字如面」放在下方，
/// > 右下角要留一块空白给二维码。不要人物，不要现代元素。
///
/// 只有「老邮票」「不要人物」「不要现代元素」进了提示词，天安门、齿孔、怀旧、别太亮、
/// 右下角留白全部蒸发。用户感觉"解析没什么用"就是这么来的。
///
/// **不让 AI 直接写提示词**，只让它填字段，编译仍走 Compiler。原因是编译器里攒着的纪律
/// （否定词转正向、画质词截断至 2 个、垫图边界四纪律、accent 色不按面积过滤）
/// 是这个产品真正的资产，AI 直接出提示词会把它们全绕过去。
public struct ModelBriefParser: BriefParser {
    public let id: String
    public let preset: AgentPreset

    public init(preset: AgentPreset) {
        self.preset = preset
        self.id = "model:\(preset.id)"
    }

    public func parse(text: String, spec: StyleSpec) async throws -> Brief {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return Brief() }

        let output = try await AgentRunner.run(
            preset: preset, prompt: Self.prompt(text: raw, spec: spec))
        if Task.isCancelled { throw VisionError.cancelled }

        let json = try JSONExtractor.extract(from: output)
        var brief = try JSONDecoder().decode(Brief.self, from: json)

        // 原文永远存着。解析一定会有错漏，原文是唯一真相，
        // 而且用户改字段时要能对照着看自己当初写了什么。
        brief.notes = raw
        return brief
    }

    /// 兜底：agent 不可用时退回正则解析，**不是**报错。
    /// 不填任何东西也必须是完整可用的产品，这条原则不变。
    public static func fallback(text: String, spec: StyleSpec) -> Brief {
        HeuristicBriefParser.parseSync(text: text, spec: spec)
    }

    // MARK: - 指令

    static func prompt(text: String, spec: StyleSpec) -> String {
        """
        你在帮一个生图工具解析用户的需求。用户拖进来一张参考图，工具已经分析出了它的风格；
        现在用户用一段话说明这次要生成什么。你的任务是把这段话读成结构化 JSON。

        ## 参考图的既有信息（供你判断默认值，不要复述进 JSON）

        - 画幅：\(spec.composition.aspectRatio)
        - 媒介：\(spec.mediumDetail ?? spec.medium.rawValue)
        - 文案安全区：\(spec.typography.safeArea ?? "（无）")

        ## 用户这次写的

        \(text)

        ## 输出这个 JSON，不要输出别的

        ```json
        {
          "schema_version": "0.1",
          "purpose": "poster | xhs_cover | wechat_cover | web_hero | banner | background | ppt | social_card",
          "aspect_ratio": "如 3:4。用户没说就按用途的常规比例，再没有就用参考图的",
          "subject": "这次要画的主体，一句话，不含风格描述",
          "subject_detail": "主体的外观细节：形状、材质、颜色、朝向、构成元素。用户提到的每一条都要在这里，别漏",
          "action": "主体在做什么。没有就 null",
          "scene": "环境、背景、氛围要求。用户说的『偏怀旧』『别太亮』这类整体调子也放这里",
          "copy": { "title": null, "subtitle": null, "body": null },
          "copy_safe_area": "top_third | bottom_third | left_half | right_half | center | upper_left | upper_right | lower_left | lower_right | none",
          "render_text_in_image": false,
          "must_keep": ["用户明确要求保留的"],
          "must_avoid": ["用户明确不要的"],
          "quality_words": [],
          "variants": 1,
          "notes": null
        }
        ```

        ## 硬性要求

        1. **用户写的每一条信息都要有归宿。** 挨句读，逐条落到某个字段里。
           落不进任何字段的，写进 `subject_detail` 或 `scene`，**不许丢**。
           这是这次解析最重要的一条——用户最不满的就是"我写的话没进去"。
        2. **不要替用户发挥。** 他没说的别加：不要补主体细节、不要补场景、不要加风格词。
           风格来自参考图，不该由你写。
        3. `copy` 只放**要出现在画面上的文字**。用户用引号括起来的、说"标题是"「写着」的才算。
           描述性的话不是文案。
        4. `copy_safe_area` 是给文字留的干净区域。用户说了"标题放下方""右下角留白"这类位置要求，
           映射到最接近的枚举值；没说就 null。
        5. `render_text_in_image` 默认 `false`（文字后期叠图层更可控）。
           只有用户明确说"把字画进图里""直接生成文字"才 `true`。
        6. `must_avoid` 只写用户真的禁止的东西，别把"别太亮"这种调子要求塞进来——那是 `scene`。
        7. 拿不准的字段填 `null`，不要编。

        只输出 JSON。
        """
    }
}
