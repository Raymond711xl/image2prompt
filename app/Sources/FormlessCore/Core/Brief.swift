import Foundation

/// 本次要生成什么。StyleSpec 回答「长什么样」，Brief 回答「画什么」——
/// 两者合起来才编得出完整提示词，只有风格没有主体是编不出来的。
///
/// 权威定义在仓库根 schema/brief.v0.1.json。

public struct CopyBlock: Codable, Sendable, Hashable {
    public var title: String?
    public var subtitle: String?
    public var body: String?

    public init(title: String? = nil, subtitle: String? = nil, body: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.body = body
    }

    public var isEmpty: Bool {
        [title, subtitle, body].allSatisfy { ($0 ?? "").isEmpty }
    }
}

public struct RefSlots: Codable, Sendable, Hashable {
    public var style: String?
    public var composition: String?
    public var subject: String?

    public init(style: String? = nil, composition: String? = nil, subject: String? = nil) {
        self.style = style
        self.composition = composition
        self.subject = subject
    }
}

public struct ProtectItem: Codable, Sendable, Hashable {
    public var element: String
    public var originalContent: String

    enum CodingKeys: String, CodingKey {
        case element
        case originalContent = "original_content"
    }

    public init(element: String, originalContent: String) {
        self.element = element
        self.originalContent = originalContent
    }
}

public struct ReplaceItem: Codable, Sendable, Hashable {
    public var target: String
    public var newContent: String

    enum CodingKeys: String, CodingKey {
        case target
        case newContent = "new_content"
    }

    public init(target: String, newContent: String) {
        self.target = target
        self.newContent = newContent
    }
}

/// 垫图局部编辑意图。四个部件对应边界控制四纪律，缺一不可。
public struct EditIntent: Codable, Sendable, Hashable {
    public var scopeAnchor: String
    public var protect: [ProtectItem]
    public var replace: [ReplaceItem]
    public var mergeRequirements: String?

    enum CodingKeys: String, CodingKey {
        case scopeAnchor = "scope_anchor"
        case protect, replace
        case mergeRequirements = "merge_requirements"
    }

    public init(
        scopeAnchor: String = "",
        protect: [ProtectItem] = [],
        replace: [ReplaceItem] = [],
        mergeRequirements: String? = nil
    ) {
        self.scopeAnchor = scopeAnchor
        self.protect = protect
        self.replace = replace
        self.mergeRequirements = mergeRequirements
    }
}

public struct Brief: Codable, Sendable, Hashable {
    public var schemaVersion: String = "0.1"
    public var purpose: String
    public var aspectRatio: String
    public var subject: String
    public var subjectDetail: String?
    public var action: String?
    public var scene: String?
    public var copy: CopyBlock?
    public var copySafeArea: String?
    /// false 时文案不写进提示词，改由后期图层叠加——文字正确性和排版更可控
    public var renderTextInImage: Bool?
    public var mustKeep: [String]?
    public var mustAvoid: [String]?
    public var refs: RefSlots?
    public var edit: EditIntent?
    public var qualityWords: [String]?
    public var variants: Int?
    public var notes: String?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case purpose
        case aspectRatio = "aspect_ratio"
        case subject
        case subjectDetail = "subject_detail"
        case action, scene, copy
        case copySafeArea = "copy_safe_area"
        case renderTextInImage = "render_text_in_image"
        case mustKeep = "must_keep"
        case mustAvoid = "must_avoid"
        case refs, edit
        case qualityWords = "quality_words"
        case variants, notes
    }

    public init(
        purpose: String = "poster",
        aspectRatio: String = "3:4",
        subject: String = "",
        subjectDetail: String? = nil,
        action: String? = nil,
        scene: String? = nil,
        copy: CopyBlock? = nil,
        copySafeArea: String? = nil,
        renderTextInImage: Bool? = nil,
        mustKeep: [String]? = nil,
        mustAvoid: [String]? = nil,
        refs: RefSlots? = nil,
        edit: EditIntent? = nil,
        qualityWords: [String]? = nil,
        variants: Int? = nil,
        notes: String? = nil
    ) {
        self.purpose = purpose
        self.aspectRatio = aspectRatio
        self.subject = subject
        self.subjectDetail = subjectDetail
        self.action = action
        self.scene = scene
        self.copy = copy
        self.copySafeArea = copySafeArea
        self.renderTextInImage = renderTextInImage
        self.mustKeep = mustKeep
        self.mustAvoid = mustAvoid
        self.refs = refs
        self.edit = edit
        self.qualityWords = qualityWords
        self.variants = variants
        self.notes = notes
    }

    public static func decode(from data: Data) throws -> Brief {
        try JSONDecoder().decode(Brief.self, from: data)
    }

    public static func decode(contentsOf url: URL) throws -> Brief {
        try decode(from: Data(contentsOf: url))
    }
}

// MARK: - 编译产物

public enum ModelId: String, Codable, Sendable, CaseIterable {
    case jimeng
    case gptImage = "gpt-image"

    public var displayName: String {
        switch self {
        case .jimeng: return "即梦 / 豆包 / 可灵"
        case .gptImage: return "GPT Image 2"
        }
    }
}

/// 垫图编辑指令的四个部件。任一为空即拒绝产出——
/// 缺失在编译期失败，而不是产出一条已知会溢出的指令。
public struct EditParts: Sendable, Hashable {
    public let scope: String
    public let protect: String
    public let replace: String
    public let noAddNoRemove: String
}

public struct CompiledPrompt: Sendable, Hashable {
    public let model: ModelId
    public let aspectRatio: String
    /// 文生图
    public let text2img: String?
    /// 垫图局部编辑（受边界四纪律约束）。仅在 brief.edit 存在时产出。
    public let img2imgEdit: String?
    /// 垫图风格参考：上传原图 + 点名要保持的形态特征。
    /// 形态这类只可意会的特征，让模型看一眼原图比纯文字准。
    public let img2imgStyleRef: String?
    /// 参考槽协议：明确告诉模型从哪张图参考什么，避免多图互相污染。
    public let refProtocol: String?
    public let notes: [String]
    public let editParts: EditParts?
}

public struct CompileError: Error, LocalizedError, Sendable {
    public let rule: String
    public let message: String

    public var errorDescription: String? { message }
}
