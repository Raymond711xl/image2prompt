import Foundation

/// 把用户随手写的一段话映射成结构化 Brief。
///
/// 为什么不直接给表单：细粒度表单会让人分散注意力，而且很多时候脑子里就是一句
/// 综合性的描述。让人先自由写完，再把理解到的东西摊开给他改——
/// **解析结果必须可编辑**，否则解析错了就没救了。
public protocol BriefParser: Sendable {
    var id: String { get }
    func parse(text: String, spec: StyleSpec) async throws -> Brief
}

/// 离线启发式解析。不联网、不花钱，保证没配 API 也能跑通整条路径。
///
/// 它一定会漏、会错——所以界面必须把结果做成可编辑的，并且明说这是粗解析。
/// 配了模型引擎之后由 ModelBriefParser 接管，这个留作兜底。
public struct HeuristicBriefParser: BriefParser {
    public let id = "heuristic"

    public init() {}

    public func parse(text: String, spec: StyleSpec) async throws -> Brief {
        Self.parseSync(text: text, spec: spec)
    }

    public static func parseSync(text: String, spec: StyleSpec) -> Brief {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)

        let purpose = detectPurpose(raw)
        let aspect = detectAspectRatio(raw) ?? defaultAspect(for: purpose, spec: spec)
        let quoted = extractQuoted(raw)
        let avoid = extractList(raw, markers: ["不要", "不能出现", "避免", "禁止", "别出现", "去掉"])
        let keep = extractList(raw, markers: ["保留", "保持", "维持"])
        let subject = detectSubject(raw) ?? ""

        var copy: CopyBlock?
        if !quoted.isEmpty {
            copy = CopyBlock(
                title: quoted.first,
                subtitle: quoted.count > 1 ? quoted[1] : nil,
                body: quoted.count > 2 ? quoted[2] : nil
            )
        }

        return Brief(
            purpose: purpose,
            aspectRatio: aspect,
            subject: subject,
            subjectDetail: nil,
            copy: copy,
            copySafeArea: nil,
            // 默认不让模型画字：文字正确性和排版后期叠图层更可控。
            // 用户明确说了"画上文字/直接生成文字"才打开。
            renderTextInImage: wantsTextInImage(raw),
            mustKeep: keep.isEmpty ? nil : keep,
            mustAvoid: avoid.isEmpty ? nil : avoid,
            notes: raw
        )
    }

    // MARK: - 用途

    private static let purposeKeywords: [(pattern: String, purpose: String)] = [
        ("公众号|微信头图|微信封面|头图", "wechat_cover"),
        ("小红书|xhs|种草封面", "xhs_cover"),
        ("网页|首屏|hero|落地页|banner图", "web_hero"),
        ("海报|kv|主视觉", "poster"),
        ("横幅|banner|条幅", "banner"),
        ("背景图|底图|壁纸", "background"),
        ("ppt|幻灯片|配图", "ppt"),
        ("社交卡片|分享卡", "social_card"),
    ]

    static func detectPurpose(_ text: String) -> String {
        let lower = text.lowercased()
        for (pattern, purpose) in purposeKeywords {
            if lower.range(of: pattern, options: .regularExpression) != nil { return purpose }
        }
        return "poster"
    }

    // MARK: - 画幅

    static func detectAspectRatio(_ text: String) -> String? {
        // 显式写了比例
        if let r = text.range(of: "\\d{1,2}\\s*[:：]\\s*\\d{1,2}", options: .regularExpression) {
            return String(text[r]).replacingOccurrences(of: "：", with: ":")
                .replacingOccurrences(of: " ", with: "")
        }
        if text.range(of: "竖版|竖构图|竖图", options: .regularExpression) != nil { return "3:4" }
        if text.range(of: "横版|横构图|横图|宽幅", options: .regularExpression) != nil { return "16:9" }
        if text.range(of: "方形|正方形|1比1", options: .regularExpression) != nil { return "1:1" }
        return nil
    }

    /// 没说画幅时，用途的常规比例优先于参考图的比例——
    /// 参考图是海报（3:4），但这次要做微信头图，就该用 2.35:1。
    static func defaultAspect(for purpose: String, spec: StyleSpec) -> String {
        switch purpose {
        case "wechat_cover": return "2.35:1"
        case "xhs_cover": return "3:4"
        case "web_hero": return "16:9"
        case "banner": return "3:1"
        case "ppt": return "16:9"
        case "social_card": return "1:1"
        default: return spec.composition.aspectRatio
        }
    }

    // MARK: - 主体

    private static let subjectMarkers = [
        "主体(?:是|换成|改成|替换为)[:：]?\\s*",
        "(?:换成|改成|替换为|替换成)\\s*",
        "(?:做|生成|画|来)一(?:张|个|幅)\\s*",
        "主体[:：]\\s*",
    ]

    static func detectSubject(_ text: String) -> String? {
        for marker in subjectMarkers {
            guard let r = text.range(of: marker, options: .regularExpression) else { continue }
            let rest = text[r.upperBound...]
            let stop = CharacterSet(charactersIn: "，。,.；;、\n")
            let piece = rest.unicodeScalars.prefix { !stop.contains($0) }
            let candidate = String(String.UnicodeScalarView(piece))
                .trimmingCharacters(in: .whitespaces)
            if !candidate.isEmpty, candidate.count <= 30 { return candidate }
        }
        // 兜底：取第一个短句，通常就是"我想要什么"
        let firstClause = text.split(whereSeparator: { "，。,.；;\n".contains($0) }).first
        if let clause = firstClause?.trimmingCharacters(in: .whitespaces), clause.count <= 30,
            !clause.isEmpty
        {
            return clause
        }
        return nil
    }

    // MARK: - 引号里的文案

    static func extractQuoted(_ text: String) -> [String] {
        let patterns = ["「([^」]+)」", "“([^”]+)”", "\"([^\"]+)\"", "『([^』]+)』"]
        var found: [String] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let ns = text as NSString
            for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                guard m.numberOfRanges > 1 else { continue }
                let piece = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
                if !piece.isEmpty, !found.contains(piece) { found.append(piece) }
            }
        }
        return found
    }

    /// 默认走"后期叠图层"，只有明确要求模型画字才打开
    static func wantsTextInImage(_ text: String) -> Bool {
        text.range(of: "画上文字|直接生成文字|文字画进去|把字写在图上", options: .regularExpression) != nil
    }

    // MARK: - 保留 / 禁止清单

    static func extractList(_ text: String, markers: [String]) -> [String] {
        var out: [String] = []
        let stop = CharacterSet(charactersIn: "，。,.；;\n")
        for marker in markers {
            var searchRange = text.startIndex..<text.endIndex
            while let r = text.range(of: marker, range: searchRange) {
                let rest = text[r.upperBound...]
                let piece = rest.unicodeScalars.prefix { !stop.contains($0) }
                let candidate = String(String.UnicodeScalarView(piece))
                    .trimmingCharacters(in: .whitespaces)
                if !candidate.isEmpty, candidate.count <= 24, !out.contains(candidate) {
                    out.append(candidate)
                }
                guard r.upperBound < text.endIndex else { break }
                searchRange = r.upperBound..<text.endIndex
            }
        }
        return out
    }
}
