import Foundation

/// 枚举值 → 提示词用词。
///
/// 这是把 StyleSpec 的离散字段翻译回自然语言的唯一出口——改词只改这里，
/// 所有适配器和快照测试同步生效。
///
/// 与 core-ts/src/compile/vocab.ts 逐字对应。两侧任何一处改词，另一侧必须跟上。
public enum Vocab {

    public static let shotCN: [Shot: String] = [
        .extremeCloseUp: "微距特写",
        .closeUp: "特写",
        .medium: "中景",
        .wide: "全景",
        .extremeWide: "大远景",
    ]

    public static let angleCN: [Angle: String] = [
        .eyeLevel: "平视",
        .lowAngle: "低角度仰拍",
        .highAngle: "微俯视角",
        .topDown: "正俯拍",
        .dutch: "倾斜构图",
    ]

    public static let mediumCN: [Medium: String] = [
        .photography: "摄影",
        .render3d: "3D 渲染",
        .vectorIllustration: "矢量插画",
        .rasterIllustration: "插画",
        .graphicDesign: "平面设计",
        .typographyPoster: "排版海报",
        .collage: "拼贴",
        .mixedMedia: "混合媒介",
        .other: "",
    ]

    public static let lightDirCN: [LightDirection: String] = [
        .front: "正面光",
        .side: "侧光",
        .back: "逆光",
        .top: "顶光",
        .bottom: "底光",
        .ambient: "环境漫射光",
        .mixed: "混合光源",
    ]

    public static let lightQualityCN: [LightQuality: String] = [
        .soft: "柔和", .hard: "硬朗", .mixed: "软硬结合",
    ]

    public static let lightContrastCN: [LightContrast: String] = [
        .flat: "几乎无明暗对比",
        .low: "低光比",
        .medium: "中等光比",
        .high: "强明暗对比",
        .dramatic: "戏剧性光比",
    ]

    public static let saturationCN: [Saturation: String] = [
        .desaturated: "近乎无彩",
        .low: "低饱和",
        .medium: "中等饱和",
        .high: "高饱和",
        .hyper: "极高饱和撞色",
    ]

    public static let temperatureCN: [Temperature: String] = [
        .cool: "冷色调", .neutral: "中性色调", .warm: "暖色调", .mixed: "冷暖对比色调",
    ]

    public static let colorContrastCN: [ContrastLevel: String] = [
        .flat: "低对比平淡",
        .low: "低对比",
        .medium: "中对比",
        .high: "高对比",
        .extreme: "极致高对比",
    ]

    public static let brightnessCN: [BrightnessKey: String] = [
        .lowKey: "暗调", .midKey: "中间调", .highKey: "亮调",
    ]

    public static let densityCN: [Density: String] = [
        .sparse: "画面元素极少、大量呼吸空间",
        .low: "低密度、克制",
        .medium: "中等密度",
        .high: "高密度排布",
        .saturated: "满版高密度",
    ]

    public static let finishCN: [String: String] = [
        "matte": "哑光", "glossy": "光泽", "metallic": "金属", "chrome": "镀铬镜面",
        "glass": "玻璃", "fabric": "织物", "paper": "纸质", "wood": "木质",
        "stone": "石材", "liquid": "液体", "translucent": "半透明",
        "rubber": "橡胶", "ceramic": "陶瓷",
    ]

    public static let textureCN: [String: String] = [
        "grain": "胶片颗粒", "noise": "噪点肌理", "paper_grain": "纸纹",
        "halftone": "半调网点", "glitch": "故障纹理", "scanline": "扫描线",
        "risograph": "孔版印刷质感", "none": "",
    ]

    public static let typefaceCN: [String: String] = [
        "grotesque_sans": "中性无衬线体", "geometric_sans": "几何无衬线体",
        "humanist_sans": "人文无衬线体", "serif": "衬线体", "slab_serif": "粗衬线体",
        "display": "装饰标题体", "script": "手写体", "calligraphy": "书法体",
        "mono": "等宽体", "none": "",
    ]

    public static let alignmentCN: [String: String] = [
        "grid": "严格网格对齐", "centered": "居中排版", "left": "左对齐",
        "right": "右对齐", "justified": "两端对齐", "free_scatter": "自由错落排版",
        "none": "",
    ]

    public static let positionCN: [String: String] = [
        "center": "画面中央", "left": "画面左侧", "right": "画面右侧",
        "top": "画面上方", "bottom": "画面下方",
        "top_left": "画面左上", "top_right": "画面右上",
        "bottom_left": "画面左下", "bottom_right": "画面右下",
        "lower_third": "画面下三分之一处", "upper_third": "画面上三分之一处",
        "none": "",
    ]

    public static let negativeRegionCN: [String: String] = [
        "top": "画面上部", "bottom": "画面下部", "left": "画面左侧", "right": "画面右侧",
        "center": "画面中央", "middle_band": "画面中部横向带状区域",
        "top_left": "画面左上", "top_right": "画面右上",
        "bottom_left": "画面左下", "bottom_right": "画面右下",
        "upper_third": "画面上三分之一", "lower_third": "画面下三分之一",
        "surrounding": "主体四周", "none": "",
    ]

    public static let safeAreaCN: [String: String] = [
        "top_third": "画面上方三分之一", "bottom_third": "画面下方三分之一",
        "left_half": "画面左半部", "right_half": "画面右半部", "center": "画面中央",
        "upper_left": "画面左上区域", "upper_right": "画面右上区域",
        "lower_left": "画面左下区域", "lower_right": "画面右下区域",
        "none": "",
    ]

    public static let purposeCN: [String: String] = [
        "web_hero": "网页 Hero 主视觉", "poster": "海报",
        "wechat_cover": "微信公众号头图", "xhs_cover": "小红书封面",
        "banner": "横幅 banner", "background": "背景图",
        "ppt": "PPT 配图", "social_card": "社交卡片",
    ]

    /// 形态语言 → 可执行的形态描述。
    ///
    /// 这是 knowledge/design-styles.md「形态词避坑」的代码化：几何圆角和有机液态是两种气质，
    /// 单写「液态/流动/膨胀」会被生图模型理解成有机波浪泡泡形态。所以几何类形态必须
    /// **主动带上排除句**，不能只说想要什么。
    public static let geometryCN: [Geometry: String] = [
        .geometricHard: "严格几何形态，平直边缘、锐利转角",
        .geometricRounded: "几何形态配大半径圆角，平直边缘、饱满但硬朗，不要波浪形有机曲线",
        .organicFluid: "有机流动形态，连续曲率、液态感轮廓",
        .organicIrregular: "有机不规则形态，手绘感边缘",
        .angularSharp: "尖锐棱角形态，硬边切割",
        .mixed: "几何与有机形态混用",
        .none: "",
    ]

    public static let edgeCN: [Edge: String] = [
        .straight: "边缘平直",
        .largeRadiusRounded: "大半径圆角",
        .smallRadiusRounded: "小半径圆角",
        .wavy: "波浪起伏边缘",
        .irregular: "不规则边缘",
        .none: "",
    ]

    /// geometry 的描述里已经含了哪些 edge 的信息。
    /// 命中的 edge 不再重复输出——否则会编出「平直边缘、锐利转角，边缘平直」这种自我重复。
    public static let edgeImpliedBy: [Geometry: [Edge]] = [
        .geometricHard: [.straight],
        .geometricRounded: [.largeRadiusRounded, .straight],
        .organicFluid: [.wavy],
        .organicIrregular: [.irregular],
        .angularSharp: [.straight],
        .mixed: [],
        .none: [.none],
    ]

    /// 光影描述无意义的媒介：纯平面设计不模拟光源，写进提示词只会把模型推向渲染感。
    public static let flatMedia: Set<Medium> = [
        .graphicDesign, .typographyPoster, .vectorIllustration, .collage,
    ]

    public enum Camp: String, Sendable {
        case geometric, organic, neutral
    }

    /// 判定某个形态枚举属于「几何」还是「有机」阵营，供 lint 使用。
    public static let geometryCamp: [Geometry: Camp] = [
        .geometricHard: .geometric,
        .geometricRounded: .geometric,
        .angularSharp: .geometric,
        .organicFluid: .organic,
        .organicIrregular: .organic,
        .mixed: .neutral,
        .none: .neutral,
    ]

    public static let edgeCamp: [Edge: Camp] = [
        .straight: .geometric,
        .largeRadiusRounded: .geometric,
        .smallRadiusRounded: .geometric,
        .wavy: .organic,
        .irregular: .organic,
        .none: .neutral,
    ]

    /// 禁止项 → 正向表述。
    ///
    /// 模型对否定词不敏感，「没有杂物」不如「纯色极简背景」。查不到映射的**不硬编**，
    /// 转而落到 notes 建议填平台负向词框——编出一句模型听不懂的否定句是净损失。
    public struct Rewrite: Sendable {
        public let pattern: String
        public let positive: String
    }

    public static let positiveRewrite: [Rewrite] = [
        .init(pattern: "杂物|杂乱|凌乱", positive: "纯色极简背景，画面整洁"),
        .init(pattern: "人物|人像|真人", positive: "画面仅有产品与环境"),
        .init(pattern: "文字|字体|标题", positive: "纯画面构图，无排版元素"),
        .init(pattern: "(?i)logo|标志|品牌", positive: "产品表面素净无标识"),
        .init(pattern: "阴影|投影", positive: "均匀布光，接触面轻柔过渡"),
        .init(pattern: "反光|高光过曝", positive: "哑光表面，柔光箱漫射打光"),
        .init(pattern: "模糊|虚化", positive: "全画面清晰锐利，大景深"),
        .init(pattern: "饱和|艳丽|花哨", positive: "低饱和克制配色"),
        .init(pattern: "渐变", positive: "纯色平涂色块"),
        .init(pattern: "手|手部", positive: "产品独立呈现，无肢体入镜"),
    ]
}
