import Foundation

/// GPT Image 2 适配器。规则源：knowledge/gpt-image.md
///
/// 与国产模型写法的最大差异：指令遵循极强，空间关系、数量、占比可以写死硬约束。
enum GPTImageAdapter {

    /// 量词会扫射到编辑边界外，必须在编译期拦下。
    private static let blanketQuantifier = "所有|全部|每一个|每个|各个|凡是|一切"
    /// 模型看不见产权，概念词圈不住范围
    private static let ownershipWords = "我们的|自己的|本方|该公司的"

    static func compile(_ spec: StyleSpec, _ brief: Brief) throws -> CompiledPrompt {
        typealias S = CompileShared
        var notes: [String] = []

        let avoid = S.rewriteAvoid(brief.mustAvoid)
        let q = S.qualityWords(brief)
        if !q.dropped.isEmpty {
            notes.append("画质词已截断至 2 个，丢弃：\(q.dropped.joined(separator: "、"))")
        }

        let text2img = buildText2Img(spec, brief, positives: avoid.positives, quality: q.words)

        var editParts: EditParts?
        var img2imgEdit: String?
        if let edit = brief.edit {
            let parts = try buildEditParts(edit)
            editParts = parts
            var instruction =
                S.join([parts.scope, parts.protect, parts.replace, parts.noAddNoRemove], "。") + "。"
            if let merge = edit.mergeRequirements, !merge.isEmpty {
                var trimmed = merge
                if trimmed.hasSuffix("。") { trimmed.removeLast() }
                instruction += trimmed + "。"
            } else {
                notes.append(
                    "brief.edit.merge_requirements 为空。融合要求（新元素匹配原图光影透视、"
                        + "接触面阴影自然）这一句决定成品像不像 P 上去的，建议补上。"
                )
            }
            img2imgEdit = instruction
        } else {
            notes.append(
                "未提供 brief.edit，不产出垫图编辑指令。换主体/改局部请填写 edit 块"
                    + "（scope_anchor + protect + replace），四个部件齐全才会编译。"
            )
        }

        if !avoid.unconvertible.isEmpty {
            notes.append(
                "GPT Image 2 对否定约束的遵循强于国产模型，以下禁止项已直接写入提示词："
                    + avoid.unconvertible.joined(separator: "、")
            )
        }

        return CompiledPrompt(
            model: .gptImage,
            aspectRatio: brief.aspectRatio,
            text2img: text2img,
            img2imgEdit: img2imgEdit,
            img2imgStyleRef: buildStyleRef(spec, brief),
            refProtocol: S.refProtocol(brief),
            notes: notes,
            editParts: editParts
        )
    }

    private static func buildText2Img(
        _ spec: StyleSpec, _ brief: Brief, positives: [String], quality: [String]
    ) -> String {
        typealias S = CompileShared
        let c = spec.composition
        let head = S.join([S.styleFamilyText(spec, lang: "cn"), Vocab.mediumCN[spec.medium]], "") + "："
        let shot = (Vocab.shotCN[c.shot] ?? "") + (Vocab.angleCN[c.angle] ?? "")

        // GPT Image 2 的强项：位置和占比可以写死
        let placement =
            c.subjectPosition == "none"
            ? "画面无明确主体"
            : S.join([
                S.join([brief.subject, brief.subjectDetail], "，"),
                "位于\(compositionAnchor(spec))，占画面约 \(S.pct(c.subjectCoverage))",
            ])

        let region = Vocab.negativeRegionCN[c.negativeSpace.region] ?? ""
        let negative =
            region.isEmpty ? nil : "\(region)为干净负空间，约占画面 \(S.pct(c.negativeSpace.ratio))"
        let safeArea = S.resolveSafeArea(spec, brief)

        let avoidClause = (brief.mustAvoid?.isEmpty ?? true)
            ? nil : "画面中不出现\(brief.mustAvoid!.joined(separator: "、"))"

        var parts: [String?] = [
            head + shot,
            placement,
            brief.action,
            brief.scene,
            S.lightingText(spec),
            S.join([S.colorText(spec), S.paletteText(spec, withHex: true)]),
            S.materialText(spec),
            S.formText(spec),
            negative,
            c.grid,
            (c.bleed ?? false) ? "图形四边出血裁切" : nil,
            S.panelText(spec),
            S.stackingText(spec),
            (safeArea != nil && brief.renderTextInImage != true)
                ? "\(safeArea!)保持干净，供后期叠加文字图层" : nil,
            S.copyText(brief, spec),
            spec.mood.joined(separator: "、") + "氛围",
        ]
        parts.append(contentsOf: positives.map { Optional($0) })
        parts.append(avoidClause)
        parts.append(contentsOf: quality.map { Optional($0) })
        return S.join(parts)
    }

    /// 主体位置锚点，尽量落成 GPT Image 2 能精确执行的空间描述。
    private static func compositionAnchor(_ spec: StyleSpec) -> String {
        let map: [String: String] = [
            "center": "画面正中",
            "left": "画面左侧",
            "right": "画面右侧",
            "top": "画面上方",
            "bottom": "画面下方",
            "top_left": "画面左上角区域",
            "top_right": "画面右上角区域",
            "bottom_left": "画面左下角区域",
            "bottom_right": "画面右下角区域",
            "lower_third": "画面下三分之一处",
            "upper_third": "画面上三分之一处",
        ]
        return map[spec.composition.subjectPosition] ?? spec.composition.subjectPosition
    }

    /// 边界控制四纪律。编辑模型有「主题一致化」倾向：大面积替换后会把画面里相似的元素
    /// 全部和谐成同一主题，还可能无中生有补充「符合主题」的新物体。
    ///
    /// 四个部件必须齐全——任一缺失在这里抛错，而不是产出一条已知会溢出的指令。
    private static func buildEditParts(_ edit: EditIntent) throws -> EditParts {
        // 纪律一：第一句先用视觉锚点圈范围
        let anchor = edit.scopeAnchor.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !anchor.isEmpty else {
            throw CompileError(
                rule: "L3.scope", message: "缺少 edit.scope_anchor：编辑指令第一句必须用看得见的视觉锚点圈定范围。")
        }
        if anchor.range(of: ownershipWords, options: .regularExpression) != nil {
            throw CompileError(
                rule: "L3.scope",
                message: "scope_anchor 使用了模型看不见产权的概念词（\"\(anchor)\"）。"
                    + "改用视觉锚点，如「画面中央偏右、带深灰色悬浮顶棚的那一个展位」。")
        }
        var scopeBody = anchor
        if scopeBody.hasSuffix("。") { scopeBody.removeLast() }
        let scope = "仅编辑\(scopeBody)，此范围以外的画面保持与原图完全一致"

        // 纪律二：保护清单点名原有内容——点名原内容等于把它锚死
        guard !edit.protect.isEmpty else {
            throw CompileError(
                rule: "L3.protect",
                message: "缺少 edit.protect：保护清单与修改清单同等重要，必须点名不许动的元素及其原有内容。")
        }
        let protectItems = try edit.protect.map { p -> String in
            let content = p.originalContent.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else {
                throw CompileError(
                    rule: "L3.protect",
                    message: "保护项「\(p.element)」未写 original_content。点名原有内容才能把它锚死。")
            }
            return "\(p.element)（原为\(content)）"
        }
        let protect = "以下元素保持与原图完全一致：\(protectItems.joined(separator: "、"))"

        // 纪律三：枚举替换目标，禁用量词
        guard !edit.replace.isEmpty else {
            throw CompileError(rule: "L3.replace", message: "缺少 edit.replace：必须逐个枚举替换目标。")
        }
        let replaceItems = try edit.replace.map { r -> String in
            if r.target.range(of: blanketQuantifier, options: .regularExpression) != nil {
                throw CompileError(
                    rule: "L3.replace",
                    message: "替换目标「\(r.target)」含扫射性量词。量词会让编辑溢出到边界外，"
                        + "请逐个枚举具体目标（如「该展位正面两块大屏 + 右侧双面灯箱」）。")
            }
            return "\(r.target)替换为\(r.newContent)"
        }
        let replace = "在上述范围内，将\(replaceItems.joined(separator: "；"))"

        // 纪律四：禁增禁删
        let noAddNoRemove = "只替换以上点名的元素，不新增任何原图中不存在的物体，不删除未点名的元素"

        return EditParts(
            scope: scope, protect: protect, replace: replace, noAddNoRemove: noAddNoRemove)
    }

    /// 垫图风格参考指令（区别于局部编辑）。模式 A 的标配输出。
    /// 中英并写：GPT Image 2 对英文风格术语响应更准。
    private static func buildStyleRef(_ spec: StyleSpec, _ brief: Brief) -> String {
        typealias S = CompileShared
        let en = spec.styleDnaEn.map { "（英文风格参考：\($0)）" } ?? ""
        let enFamily = S.styleFamilyText(spec, lang: "en")
        return S.join(
            [
                "上传参考图，仅作风格参考",
                "提取其风格语言：\(S.join([S.formText(spec), S.materialText(spec), S.colorText(spec)], "；"))",
                enFamily.isEmpty ? nil : "风格流派 \(enFamily)",
                "画面内容改为\(S.join([brief.subject, brief.subjectDetail], "，"))，按新主体重新构图",
                "参考图的具体物体、场景和文字不进入生成结果",
            ], "，") + en
    }
}
