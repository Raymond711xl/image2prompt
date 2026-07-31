import Foundation

// StyleSpec v0.2 的 Swift 映射。权威定义在仓库根 schema/stylespec.v0.2.json。
//
// 这里不做 JSON Schema 运行时校验：Codable 解码失败即非法输入，类型系统就是 schema。
// TypeScript 侧需要 ajv 是因为 TS 类型在运行时会被擦除，Swift 不会。

public enum AdType: String, Codable, Sendable, CaseIterable {
    case heroShot = "hero_shot"
    case lifestyle
    case moodPoster = "mood_poster"
    case background
    case promoBanner = "promo_banner"
    case concept
    case other
}

public enum Medium: String, Codable, Sendable, CaseIterable {
    case photography
    case render3d = "3d_render"
    case vectorIllustration = "vector_illustration"
    case rasterIllustration = "raster_illustration"
    case graphicDesign = "graphic_design"
    case typographyPoster = "typography_poster"
    case collage
    case mixedMedia = "mixed_media"
    case other
}

/// 形态语言。**写错一个词生成方向就全偏**——几何圆角和有机液态是两种气质。
/// 调参盘的风格轴 X 就在这个枚举上做邻近移动。
public enum Geometry: String, Codable, Sendable, CaseIterable {
    case geometricHard = "geometric_hard"
    case geometricRounded = "geometric_rounded"
    case organicFluid = "organic_fluid"
    case organicIrregular = "organic_irregular"
    case angularSharp = "angular_sharp"
    case mixed
    case none
}

public enum Edge: String, Codable, Sendable, CaseIterable {
    case straight
    case largeRadiusRounded = "large_radius_rounded"
    case smallRadiusRounded = "small_radius_rounded"
    case wavy
    case irregular
    case none
}

public enum Shot: String, Codable, Sendable {
    case extremeCloseUp = "extreme_close_up"
    case closeUp = "close_up"
    case medium
    case wide
    case extremeWide = "extreme_wide"
}

public enum Angle: String, Codable, Sendable {
    case eyeLevel = "eye_level"
    case lowAngle = "low_angle"
    case highAngle = "high_angle"
    case topDown = "top_down"
    case dutch
}

/// 画面密度。调参盘的风格轴 Y。
public enum Density: String, Codable, Sendable, CaseIterable {
    case sparse, low, medium, high, saturated
}

public enum Symmetry: String, Codable, Sendable {
    case symmetric
    case asymmetricBalanced = "asymmetric_balanced"
    case asymmetricDynamic = "asymmetric_dynamic"
}

public enum PaletteRole: String, Codable, Sendable {
    case base, secondary, accent
}

/// 饱和度。色彩盘的独立滑杆。
public enum Saturation: String, Codable, Sendable, CaseIterable {
    case desaturated, low, medium, high, hyper
}

/// 色温。色彩盘 X 轴。
public enum Temperature: String, Codable, Sendable, CaseIterable {
    case cool, neutral, warm, mixed
}

public enum ContrastLevel: String, Codable, Sendable {
    case flat, low, medium, high, extreme
}

/// 明暗调性。色彩盘 Y 轴。
public enum BrightnessKey: String, Codable, Sendable, CaseIterable {
    case lowKey = "low_key"
    case midKey = "mid_key"
    case highKey = "high_key"
}

public enum LightDirection: String, Codable, Sendable {
    case front, side, back, top, bottom, ambient, mixed
}

public enum LightQuality: String, Codable, Sendable {
    case soft, hard, mixed
}

public enum LightContrast: String, Codable, Sendable {
    case flat, low, medium, high, dramatic
}

public enum LeakageSeverity: String, Codable, Sendable {
    case low, medium, high
}

public enum StyleFamilyRole: String, Codable, Sendable {
    case primary, borrowed
}

/// v0.2 新增：这段文字能不能确定原样照抄。unclear 时编译层不得当 literal text 处理。
public enum OcrStatus: String, Codable, Sendable, CaseIterable {
    case exact, approx, unclear
}

/// v0.2 新增：文字和画面其他元素相比大致的前后关系，不做精确 z-index。
public enum TextLayer: String, Codable, Sendable, CaseIterable {
    case front, middle, back
}

/// v0.2 新增：文字是否被变形处理。
public enum TextDistortion: String, Codable, Sendable, CaseIterable {
    case none
    case curvedPath = "curved_path"
    case perspectiveSkew = "perspective_skew"
    case rotated
    case stretched
    case outlinedLayered = "outlined_layered"
    case other
}

/// v0.2 新增：相对画面里其他文字的大小级别，不是像素字号。
public enum RelativeSize: String, Codable, Sendable, CaseIterable {
    case largest, large, medium, small, smallest
}

/// v0.2 新增：载体判断——这是完整平面设计图，还是印在物体上的照片、截图、实景照片。
public enum CarrierTypeValue: String, Codable, Sendable, CaseIterable {
    case flatDesign = "flat_design"
    case printOnObject = "print_on_object"
    case screenshot
    case photoScene = "photo_scene"
    case unknown
}

// MARK: - 组合类型

public struct StyleFamily: Codable, Sendable, Hashable {
    public let name: String
    public let nameEn: String
    public let confidence: Double
    public let evidence: String
    public let role: StyleFamilyRole?

    enum CodingKeys: String, CodingKey {
        case name
        case nameEn = "name_en"
        case confidence, evidence, role
    }
}

public struct SourceInfo: Codable, Sendable, Hashable {
    public let path: String?
    public let url: String?
    public let analyzedAt: String
    public let analyzer: String
    public let temporary: Bool?
    /// v0.2 新增：像素宽高，直接读文件，不由分析模型猜测。
    public let width: Int
    public let height: Int
    /// v0.2 新增：width/height 精确值，composition.aspectRatio 仍保留做类别展示。
    public let aspectExact: Double

    enum CodingKeys: String, CodingKey {
        case path, url
        case analyzedAt = "analyzed_at"
        case analyzer, temporary, width, height
        case aspectExact = "aspect_exact"
    }
}

public struct OnImageText: Codable, Sendable, Hashable {
    public let text: String
    public let position: String
    public let role: String?
    /// v0.2 新增
    public let layer: TextLayer?
    /// v0.2 新增：exact/approx/unclear。unclear 时编译层不得当 literal text。
    public let ocrStatus: OcrStatus
    /// v0.2 新增：实际分行方式，按视觉顺序列出每一行。
    public let lineBreaks: [String]?
    /// v0.2 新增：这段文字的颜色，优先 hex。
    public let color: String?
    /// v0.2 新增：相对画面里其他文字的大小级别。
    public let relativeSize: RelativeSize?
    /// v0.2 新增
    public let distortion: TextDistortion?
    /// v0.2 新增：只有明显不同于 typography.typefaceClass 时才填。
    public let typefaceNote: String?

    enum CodingKeys: String, CodingKey {
        case text, position, role, layer
        case ocrStatus = "ocr_status"
        case lineBreaks = "line_breaks"
        case color
        case relativeSize = "relative_size"
        case distortion
        case typefaceNote = "typeface_note"
    }
}

/// v0.2 新增：载体判断，confidence 低时保留候选，不擅自定死成一种。
public struct CarrierType: Codable, Sendable, Hashable {
    public let value: CarrierTypeValue
    public let confidence: Double
    public let candidates: [String]?
}

/// 内容层隔离区。**本块内容禁止出现在 style_dna 中**——这条隔离是整个产品成立的前提。
/// 换主体时 content 整个丢弃，其余字段完整保留。
public struct ContentLayer: Codable, Sendable, Hashable {
    public let subject: String
    public let scene: String
    public let brandMarks: [String]
    public let onImageText: [OnImageText]
    public let keywords: [String]
    /// v0.2 新增
    public let carrierType: CarrierType
    /// v0.2 新增：默认 true——只描述画面里实际可见的内容，不得用品牌/IP 常识补全画面外的内容。
    public let visibleOnly: Bool?
    /// v0.2 新增：容易触发生成模型自身常识联想的品牌/IP/知名作品名称。
    public let externalExpansionRisk: [String]?

    enum CodingKeys: String, CodingKey {
        case subject, scene
        case brandMarks = "brand_marks"
        case onImageText = "on_image_text"
        case keywords
        case carrierType = "carrier_type"
        case visibleOnly = "visible_only"
        case externalExpansionRisk = "external_expansion_risk"
    }
}

public struct NegativeSpace: Codable, Sendable, Hashable {
    public let region: String
    public let ratio: Double
    public let note: String?
}

/// v0.2 新增：只有 panelCount > 1 时才有意义的一块版面。
public struct Panel: Codable, Sendable, Hashable {
    public let region: String
    public let role: String
}

public struct Composition: Codable, Sendable, Hashable {
    public let shot: Shot
    public let angle: Angle
    public let aspectRatio: String
    public let subjectPosition: String
    public let subjectCoverage: Double
    public let negativeSpace: NegativeSpace
    public let grid: String?
    public let density: Density
    public let bleed: Bool?
    public let layers: Int?
    public let symmetry: Symmetry?
    public let visualFlow: String?
    /// v0.2 新增：画面实际是几个独立版块拼成的，单张设计图为 1。
    public let panelCount: Int
    /// v0.2 新增：只有 panelCount > 1 时才有值。
    public let panels: [Panel]?
    /// v0.2 新增：主要元素按前后顺序列出（从最前到最后），只要相对顺序。
    public let elementStacking: [String]?

    enum CodingKeys: String, CodingKey {
        case shot, angle
        case aspectRatio = "aspect_ratio"
        case subjectPosition = "subject_position"
        case subjectCoverage = "subject_coverage"
        case negativeSpace = "negative_space"
        case grid, density, bleed, layers, symmetry
        case visualFlow = "visual_flow"
        case panelCount = "panel_count"
        case panels
        case elementStacking = "element_stacking"
    }
}

/// 色板条目。hex + 占比让色彩偏移成为**真正的运算**而不是换形容词——
/// 保色相降饱和、旋转色相、只换 accent，全都是确定性计算，可实时预览色块。
public struct PaletteEntry: Codable, Sendable, Hashable {
    public let hex: String
    public let ratio: Double
    public let role: PaletteRole
    public let nameCn: String?

    enum CodingKeys: String, CodingKey {
        case hex, ratio, role
        case nameCn = "name_cn"
    }
}

public struct ColorInfo: Codable, Sendable, Hashable {
    public let saturation: Saturation
    public let temperature: Temperature
    public let contrast: ContrastLevel
    public let harmony: String?
    public let brightnessKey: BrightnessKey?

    enum CodingKeys: String, CodingKey {
        case saturation, temperature, contrast, harmony
        case brightnessKey = "brightness_key"
    }
}

public struct Lighting: Codable, Sendable, Hashable {
    public let direction: LightDirection
    public let quality: LightQuality
    public let contrast: LightContrast
    public let sources: [String]?
    public let timeOfDay: String?
    public let note: String?

    enum CodingKeys: String, CodingKey {
        case direction, quality, contrast, sources
        case timeOfDay = "time_of_day"
        case note
    }
}

public struct Surface: Codable, Sendable, Hashable {
    public let uhere: String
    public let finish: String
    public let detail: String?

    // schema 里字段名是 where，Swift 关键字，映射掉
    enum CodingKeys: String, CodingKey {
        case uhere = "where"
        case finish, detail
    }
}

public struct MaterialInfo: Codable, Sendable, Hashable {
    public let surfaces: [Surface]
    public let textureOverlay: [String]?

    enum CodingKeys: String, CodingKey {
        case surfaces
        case textureOverlay = "texture_overlay"
    }
}

public struct FormLanguage: Codable, Sendable, Hashable {
    public let geometry: Geometry
    public let edge: Edge
    public let cornerRadiusNote: String?
    public let strokeWeight: String?
    public let repetition: String?
    public let gapRule: String?

    enum CodingKeys: String, CodingKey {
        case geometry, edge
        case cornerRadiusNote = "corner_radius_note"
        case strokeWeight = "stroke_weight"
        case repetition
        case gapRule = "gap_rule"
    }
}

public struct Typography: Codable, Sendable, Hashable {
    public let present: Bool
    public let typefaceClass: String?
    public let weightContrast: String?
    public let sizeHierarchy: [String]?
    public let alignment: String?
    public let letterCase: String?
    public let safeArea: String?
    /// v0.2 新增：多段文字靠什么隐形关系互相咬合（共用对齐线、顶边对齐、行距字块间距统一比例）。
    public let implicitAlignment: String?
    public let note: String?

    enum CodingKeys: String, CodingKey {
        case present
        case typefaceClass = "typeface_class"
        case weightContrast = "weight_contrast"
        case sizeHierarchy = "size_hierarchy"
        case alignment
        case letterCase = "case"
        case safeArea = "safe_area"
        case implicitAlignment = "implicit_alignment"
        case note
    }
}

public struct ContentLeakage: Codable, Sendable, Hashable {
    public let field: String
    public let phrase: String
    public let severity: LeakageSeverity
}

public struct Confidence: Codable, Sendable, Hashable {
    public let overall: Double
    public let uncertainFields: [String]

    enum CodingKeys: String, CodingKey {
        case overall
        case uncertainFields = "uncertain_fields"
    }
}

// MARK: - StyleSpec

public struct StyleSpec: Codable, Sendable, Hashable {
    public let schemaVersion: String
    public let source: SourceInfo
    public let adType: AdType
    public let medium: Medium
    public let mediumDetail: String?
    public let styleFamily: [StyleFamily]
    public let content: ContentLayer
    public let composition: Composition
    public let palette: [PaletteEntry]
    public let color: ColorInfo
    public let lighting: Lighting
    public let material: MaterialInfo
    public let formLanguage: FormLanguage
    public let typography: Typography
    public let mood: [String]
    public let useCases: [String]?
    /// 与画面内容无关、可套用任何主体的风格描述块。模式 A 的核心交付。
    public let styleDna: String
    public let styleDnaEn: String?
    public let contentLeakage: [ContentLeakage]?
    public let confidence: Confidence
    public let notes: String?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case source
        case adType = "ad_type"
        case medium
        case mediumDetail = "medium_detail"
        case styleFamily = "style_family"
        case content, composition, palette, color, lighting, material
        case formLanguage = "form_language"
        case typography, mood
        case useCases = "use_cases"
        case styleDna = "style_dna"
        case styleDnaEn = "style_dna_en"
        case contentLeakage = "content_leakage"
        case confidence, notes
    }
}

// MARK: - 编解码

extension StyleSpec {
    public static func decode(from data: Data) throws -> StyleSpec {
        try JSONDecoder().decode(StyleSpec.self, from: data)
    }

    public static func decode(contentsOf url: URL) throws -> StyleSpec {
        try decode(from: Data(contentsOf: url))
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}
