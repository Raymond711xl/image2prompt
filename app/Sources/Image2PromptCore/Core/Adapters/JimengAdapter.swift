import Foundation

/// 即梦 / 豆包 / 可灵适配器。规则源：knowledge/jimeng.md
///
/// 基本公式：风格媒介 + 景别视角 + 主体（外观细节）+ 动作状态 + 场景环境
///          + 光线 + 色调 + 氛围 + 画质词
///
/// 关键约束（由代码保证，不靠模型自觉）：
/// - 先重后轻：模型对开头权重更高，风格 + 主体必须排最前。
/// - 正向表述：禁止项转正向，转不了的不写进提示词。
/// - 画质词 ≤ 2：堆砌只会稀释权重。
/// - 画幅比例在平台界面选，提示词里只写构图意图。
enum JimengAdapter {

    static func compile(_ spec: StyleSpec, _ brief: Brief) -> CompiledPrompt {
        typealias S = CompileShared
        var notes: [String] = []

        let styleHead = S.join([S.styleFamilyText(spec, lang: "cn"), Vocab.mediumCN[spec.medium]], "")
        let shot =
            (Vocab.shotCN[spec.composition.shot] ?? "")
            + (Vocab.angleCN[spec.composition.angle] ?? "")
        let subject = S.join([brief.subject, brief.subjectDetail], "，")

        let avoid = S.rewriteAvoid(brief.mustAvoid)
        if !avoid.unconvertible.isEmpty {
            notes.append(
                "以下禁止项无法转成正向表述，不写进提示词（模型对否定词不敏感）；"
                    + "请在平台的负向词/排除词输入框填写：\(avoid.unconvertible.joined(separator: "、"))"
            )
        }

        let q = S.qualityWords(brief)
        if !q.dropped.isEmpty {
            notes.append("画质词点到为止，已丢弃超出 2 个的部分：\(q.dropped.joined(separator: "、"))")
        }

        // 先重后轻。顺序即权重，不要随意调整。
        var parts: [String?] = [
            styleHead,
            shot,
            subject,
            brief.action,
            brief.scene,
            S.lightingText(spec),
            S.join([S.colorText(spec), S.paletteText(spec, withHex: false)]),
            S.materialText(spec),
            S.formText(spec),
            S.compositionText(spec, brief),
            S.copyText(brief, spec),
            spec.mood.joined(separator: "、") + "氛围",
        ]
        parts.append(contentsOf: avoid.positives.map { Optional($0) })
        parts.append(contentsOf: q.words.map { Optional($0) })
        let text2img = S.join(parts)

        if brief.renderTextInImage != true, let copy = brief.copy, !copy.isEmpty {
            notes.append(
                "文案未写进提示词：先生成主视觉，标题后期以可编辑图层叠加，文字正确性和排版更可控。"
                    + "需要模型直接画字请把 brief.render_text_in_image 设为 true。"
            )
        }

        notes.append("画幅比例 \(brief.aspectRatio) 请在平台界面选择，提示词里只写了构图意图。")

        return CompiledPrompt(
            model: .jimeng,
            aspectRatio: brief.aspectRatio,
            text2img: text2img,
            // 边界控制四纪律是 GPT Image 2 的编辑能力，即梦侧不产出局部编辑指令
            img2imgEdit: nil,
            img2imgStyleRef: buildStyleRef(spec, brief),
            refProtocol: S.refProtocol(brief),
            notes: notes,
            editParts: nil
        )
    }

    /// 图生图风格参考指令。
    /// 形态这类「只可意会」的特征，让模型看一眼原图比纯文字描述准得多——
    /// 文生图两轮都不像时，这是第一修复路线。
    private static func buildStyleRef(_ spec: StyleSpec, _ brief: Brief) -> String {
        typealias S = CompileShared
        let keep = S.join(
            [
                S.formText(spec),
                "\(S.colorText(spec))的色彩关系",
                S.materialText(spec),
            ], "；")
        return S.join(
            [
                "上传参考图作为风格参考",
                "保持其\(keep)",
                "画面主体替换为\(S.join([brief.subject, brief.subjectDetail], "，"))",
                "仅提取参考图的视觉风格，画面内容与文字全部按新主体重新绘制",
            ], "，")
    }
}
