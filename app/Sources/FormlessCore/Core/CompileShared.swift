import Foundation

/// 适配器共用的片段生成。与 core-ts/src/compile/shared.ts 逐字对应。
enum CompileShared {

    /// 过滤空片段并用分隔符连接。适配器里到处是可选片段，统一在这里收口。
    static func join(_ parts: [String?], _ sep: String = "，") -> String {
        parts
            .compactMap { $0 }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: sep)
    }

    static func pct(_ n: Double) -> String {
        "\(Int((n * 100).rounded()))%"
    }

    /// 色板描述。
    ///
    /// 主色/辅色按面积过滤（占比过小的色相写进提示词只会稀释权重），但 **accent 一律保留**：
    /// 「低明度墨绿 + 高明度米白 + 一点铬黄」里的铬黄可能只占 0.4% 面积，却是这张图的签名色，
    /// 按面积滤掉就把风格的关键一笔丢了。
    static func paletteText(_ spec: StyleSpec, withHex: Bool) -> String {
        let roleCN: [PaletteRole: String] = [.base: "主色", .secondary: "辅色", .accent: "点缀色"]
        let items =
            spec.palette
            .filter { $0.role == .accent || $0.ratio >= 0.05 }
            .sorted { $0.ratio > $1.ratio }
            .map { c -> String in
                let name = c.nameCn ?? c.hex
                let hex = (withHex && c.nameCn != nil) ? "（\(c.hex)）" : ""
                let amount = c.ratio < 0.02 ? "小面积点缀" : "约占 \(pct(c.ratio))"
                return "\(roleCN[c.role] ?? "")\(name)\(hex)\(amount)"
            }
        return items.joined(separator: "、")
    }

    static func colorText(_ spec: StyleSpec) -> String {
        join([
            Vocab.saturationCN[spec.color.saturation],
            Vocab.temperatureCN[spec.color.temperature],
            Vocab.colorContrastCN[spec.color.contrast],
            spec.color.brightnessKey.flatMap { Vocab.brightnessCN[$0] },
        ])
    }

    /// 光线描述。
    ///
    /// 纯平面媒介且判为无光比时，不编出「柔和环境漫射光」这类描述——
    /// 它会把生图模型往三维渲染感上推，正好毁掉平面感。
    static func lightingText(_ spec: StyleSpec) -> String {
        let isFlatArtwork =
            Vocab.flatMedia.contains(spec.medium)
            && spec.lighting.contrast == .flat
            && (spec.lighting.sources?.isEmpty ?? true)
        if isFlatArtwork { return "纯平面无光影模拟，无投影无高光" }

        let sources = (spec.lighting.sources?.isEmpty ?? true)
            ? nil : spec.lighting.sources?.joined(separator: "、")
        let quality = Vocab.lightQualityCN[spec.lighting.quality] ?? ""
        let direction = Vocab.lightDirCN[spec.lighting.direction] ?? ""
        return join([
            sources,
            quality + direction,
            Vocab.lightContrastCN[spec.lighting.contrast],
            spec.lighting.timeOfDay,
        ])
    }

    static func materialText(_ spec: StyleSpec) -> String {
        let surfaces =
            spec.material.surfaces
            .map { s -> String in
                let finish = Vocab.finishCN[s.finish] ?? s.finish
                let detail = s.detail.map { "（\($0)）" } ?? ""
                return "\(s.uhere)呈\(finish)质感\(detail)"
            }
            .joined(separator: "、")

        let overlay = (spec.material.textureOverlay ?? [])
            .filter { $0 != "none" }
            .map { Vocab.textureCN[$0] ?? $0 }
            .joined(separator: "、")

        return join([surfaces, overlay])
    }

    /// 形态描述。几何类形态会自带排除句，见 Vocab.geometryCN 的说明。
    static func formText(_ spec: StyleSpec) -> String {
        let f = spec.formLanguage
        let edgeImplied = (Vocab.edgeImpliedBy[f.geometry] ?? []).contains(f.edge)
        return join([
            Vocab.geometryCN[f.geometry],
            edgeImplied ? nil : Vocab.edgeCN[f.edge],
            f.cornerRadiusNote,
            f.gapRule,
            f.repetition,
        ])
    }

    static func compositionText(_ spec: StyleSpec, _ brief: Brief) -> String {
        let c = spec.composition
        let pos = Vocab.positionCN[c.subjectPosition] ?? c.subjectPosition
        let subjectPart =
            c.subjectPosition == "none"
            ? nil : "主体位于\(pos)、占画面约 \(pct(c.subjectCoverage))"

        let region = Vocab.negativeRegionCN[c.negativeSpace.region] ?? ""
        let negative = region.isEmpty ? nil : "\(region)保留约 \(pct(c.negativeSpace.ratio)) 负空间"
        let safeArea = resolveSafeArea(spec, brief)

        // visual_flow 刻意不编译：动线描述必然依附原图的具体元素，换主体后不成立
        return join([
            subjectPart,
            negative,
            safeArea.map { "\($0)保持干净可排版" },
            c.grid,
            Vocab.densityCN[c.density],
            (c.bleed ?? false) ? "图形四边出血裁切" : nil,
        ])
    }

    /// 面板结构。panelCount > 1 时明确告诉生成模型这是多面板拼合画面，不要拍扁成一张连续场景——
    /// v0.1 时代最容易犯的错就是这个（作品页截图里的上下两张图被合并成一张）。
    static func panelText(_ spec: StyleSpec) -> String? {
        let c = spec.composition
        guard c.panelCount > 1 else { return nil }
        let base = "画面由 \(c.panelCount) 个独立版块拼合而成，各版块保持独立边界，不要合并成一个连续场景"
        guard let panels = c.panels, !panels.isEmpty else { return base }
        let detail = panels.enumerated()
            .map { i, p in "第\(i + 1)块（\(p.region)）：\(p.role)" }
            .joined(separator: "；")
        return "\(base)——\(detail)"
    }

    /// 元素前后顺序（基础版，只给相对顺序，不给坐标）。
    static func stackingText(_ spec: StyleSpec) -> String? {
        guard let order = spec.composition.elementStacking, !order.isEmpty else { return nil }
        return "画面元素前后顺序（从前到后）：\(order.joined(separator: " → "))"
    }

    /// 文案安全区：Brief 显式指定优先，否则继承 StyleSpec 的 typography.safe_area。
    static func resolveSafeArea(_ spec: StyleSpec, _ brief: Brief) -> String? {
        if let area = brief.copySafeArea, !area.isEmpty, area != "none" {
            return Vocab.safeAreaCN[area] ?? area
        }
        guard let area = spec.typography.safeArea, !area.isEmpty else { return nil }
        return area
    }

    static func styleFamilyText(_ spec: StyleSpec, lang: String) -> String {
        spec.styleFamily
            .map { lang == "cn" ? $0.name : $0.nameEn }
            .filter { !$0.isEmpty }
            .joined(separator: " + ")
    }

    struct AvoidResult {
        /// 可转成正向表述的，直接进提示词
        let positives: [String]
        /// 转不了的，落到 notes 建议用平台负向词框
        let unconvertible: [String]
    }

    /// 禁止项处理。模型对否定词不敏感——「没有杂物」不如「纯色极简背景」。
    /// 查不到映射时**不硬造否定句**，交还给用户在平台负向词框填写。
    static func rewriteAvoid(_ mustAvoid: [String]?) -> AvoidResult {
        var positives: [String] = []
        var unconvertible: [String] = []
        for term in mustAvoid ?? [] {
            if let hit = Vocab.positiveRewrite.first(where: { rule in
                term.range(of: rule.pattern, options: .regularExpression) != nil
            }) {
                if !positives.contains(hit.positive) { positives.append(hit.positive) }
            } else {
                unconvertible.append(term)
            }
        }
        return AvoidResult(positives: positives, unconvertible: unconvertible)
    }

    /// 画质词点到为止：最多 2 个，多余的丢弃并在 notes 里说明。
    static func qualityWords(_ brief: Brief) -> (words: [String], dropped: [String]) {
        let all = brief.qualityWords ?? []
        return (Array(all.prefix(2)), Array(all.dropFirst(2)))
    }

    /// 三个参考槽的分工协议。
    /// 必须明确告诉模型「从哪张图参考什么」，否则多张参考图会互相污染。
    static func refProtocol(_ brief: Brief) -> String? {
        guard let refs = brief.refs else { return nil }
        var lines: [String] = []
        if let style = refs.style, !style.isEmpty {
            lines.append("图 A（\(style)）：只参考视觉风格——色彩、材质、光线、质感。忽略其画面内容与构图。")
        }
        if let composition = refs.composition, !composition.isEmpty {
            lines.append("图 B（\(composition)）：只参考构图——主体位置、留白分布、画幅比例。忽略其风格与主体外观。")
        }
        if let subject = refs.subject, !subject.isEmpty {
            lines.append("图 C（\(subject)）：只参考主体外观——形状、比例、材质细节。忽略其背景、光线与色调。")
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    /// 画面文字片段。render_text_in_image 为 false 时不写进提示词，改由后期图层叠加。
    static func copyText(_ brief: Brief, _ spec: StyleSpec) -> String? {
        guard brief.renderTextInImage == true else { return nil }
        guard let copy = brief.copy else { return nil }

        let safeArea = resolveSafeArea(spec, brief)
        let face = spec.typography.typefaceClass.flatMap { key -> String? in
            let v = Vocab.typefaceCN[key]
            return (v?.isEmpty ?? true) ? nil : v
        }
        let align = spec.typography.alignment.flatMap { key -> String? in
            let v = Vocab.alignmentCN[key]
            return (v?.isEmpty ?? true) ? nil : v
        }

        var bits: [String] = []
        if let title = copy.title, !title.isEmpty {
            bits.append("\(safeArea ?? "画面上方")排版标题文字\"\(title)\"")
        }
        if let subtitle = copy.subtitle, !subtitle.isEmpty { bits.append("副标题\"\(subtitle)\"") }
        if let body = copy.body, !body.isEmpty { bits.append("正文小字\"\(body)\"") }
        if bits.isEmpty { return nil }

        return join(bits.map { Optional($0) } + [face, align])
    }
}
