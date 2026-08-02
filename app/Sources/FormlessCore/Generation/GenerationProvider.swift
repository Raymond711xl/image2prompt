import Foundation

/// 生图引擎的统一接口。与 `VisionProvider` 对称：那个把图变成 StyleSpec，这个把提示词变成图。
///
/// 刻意不复用 `VisionProvider`：识图是"发一段指令、收一段文字"，生图是
/// "发一段指令、收一个文件"，产物形状不同，错误也不同（生图会出现
/// "跑完了但图没落盘"和"跑完了但提示词被改写"这两种识图没有的失败）。
public protocol GenerationProvider: Sendable {
    /// 稳定标识，存设置用
    var id: String { get }
    /// 设置界面里显示的名字
    var displayName: String { get }

    func generate(_ request: GenerationRequest) async throws -> GenerationResult
}

/// 一次生图任务。
///
/// `prompt` 是编译器已经产出的最终提示词，**这里不做任何加工**——
/// 加工过就没法判断生成结果反映的是编译器还是中间环节。
public struct GenerationRequest: Sendable, Hashable {
    public let prompt: String
    /// 只用于给产物命名和记录，不参与提示词
    public let model: ModelId
    /// 期望画幅，如 "3:4"。注意：Codex 内置模式**控制不了精确尺寸**，
    /// 只能用来提示取向，实际尺寸以产物为准。
    public let aspectRatio: String
    /// 本次任务的唯一目录。必须唯一——并发时靠它隔离，不靠"最新的一张"。
    public let jobDirectory: URL

    public init(prompt: String, model: ModelId, aspectRatio: String, jobDirectory: URL) {
        self.prompt = prompt
        self.model = model
        self.aspectRatio = aspectRatio
        self.jobDirectory = jobDirectory
    }
}

public struct GenerationResult: Sendable, Hashable {
    public let imageURL: URL
    /// 我们实际发出去的提示词（编译器产出 + 一句画幅）。
    /// 比对基准是它，不是 `request.prompt`——画幅那一句是我们自己加的，不算改写。
    public let sentPrompt: String
    /// agent 自称实际传给生图工具的提示词
    public let finalPrompt: String?
    /// 我们自己用 ImageIO 量的真实像素，**不采信 agent 的自述**——
    /// 冒烟测试里 agent 报的 size 是它事后拉伸的结果，不是生成尺寸。
    public let pixelWidth: Int
    public let pixelHeight: Int
    /// agent 自述走的哪条路（builtin_image_gen / cli_fallback / …）。
    /// 用来发现 skill 没触发——本机 skill 装得多时描述会被截断，触发不是必然。
    public let toolUsed: String?

    public init(
        imageURL: URL, sentPrompt: String, finalPrompt: String?,
        pixelWidth: Int, pixelHeight: Int, toolUsed: String?
    ) {
        self.imageURL = imageURL
        self.sentPrompt = sentPrompt
        self.finalPrompt = finalPrompt
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.toolUsed = toolUsed
    }

    /// 提示词有没有被中间环节改写。
    ///
    /// 这是整条链路里唯一能证明实验有效的判据：图偏了，没有这一条就分不清
    /// 是编译器的锅还是 agent 改写的锅。
    public var promptIsVerbatim: Bool { finalPrompt == sentPrompt }

    public var pixelSize: String { "\(pixelWidth)×\(pixelHeight)" }
}

public enum GenerationError: Error, LocalizedError, Sendable {
    case unavailable(String)
    case agentFailed(String)
    /// agent 正常退出，但没有产出可用结果
    case noResult(String)
    /// 结果文件在，但不是能解码的图片
    case undecodableImage(URL)
    case reportedFailure(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .unavailable(let detail):
            return "生图引擎不可用：\(detail)"
        case .agentFailed(let detail):
            return "生图 agent 出错：\(detail)"
        case .noResult(let detail):
            return "agent 跑完了但没拿到结果：\(detail)"
        case .undecodableImage(let url):
            return "产出的文件不是能解码的图片：\(url.lastPathComponent)"
        case .reportedFailure(let message):
            return "生图失败：\(message)"
        case .cancelled:
            return "已取消"
        }
    }
}
