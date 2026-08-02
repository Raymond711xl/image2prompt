import Foundation

/// 识图引擎的统一接口。
///
/// 这个协议存在的理由：产品未来要让别人也能用，用户得能填自己的多模态 API。
/// 现主流 LLM API 基本都支持传图理解，而国内平台绝大多数提供 OpenAI 兼容端点——
/// 所以三个实现就能覆盖绝大部分市场：
///
///   MockVisionProvider          假数据，开发和测试用，不花钱不需要 key
///   AnthropicProvider           原生协议
///   OpenAICompatProvider        base_url + key + model 三个字段，覆盖 OpenAI /
///                               通义 / 智谱 / 豆包 / Kimi / MiniMax 等
///   GeminiProvider              协议不同，需单独实现
///
/// 上层（队列、UI）只认这个协议，换引擎不动任何调用方代码。
public protocol VisionProvider: Sendable {
    /// 稳定标识，存设置用
    var id: String { get }
    /// 设置界面里显示的名字
    var displayName: String { get }
    /// 是否需要 API key。Mock 不需要。
    var requiresAPIKey: Bool { get }

    /// 看一张图，产出 StyleSpec。
    func analyze(imageURL: URL) async throws -> StyleSpec
}

public enum VisionError: Error, LocalizedError, Sendable {
    case unreadableImage(URL)
    case missingCredentials(provider: String)
    /// 真正的网络层失败（HTTP API provider 用）。本地 agent 走子进程，不是网络请求，
    /// 别再复用这个 case——超时/非零退出/找不到可执行文件都不是"网络请求失败"，
    /// 报错要说真话，不然用户永远猜不出实际原因。
    case transport(String)
    /// 本地 agent 子进程失败：超时、非零退出、启动失败、找不到可执行文件。
    case agentFailed(String)
    case malformedResponse(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .unreadableImage(let url):
            return "读不到图片：\(url.lastPathComponent)"
        case .missingCredentials(let provider):
            return "\(provider) 没有配置 API key，请到设置里填写"
        case .transport(let detail):
            return "网络请求失败：\(detail)"
        case .agentFailed(let detail):
            return "本地 agent 出错：\(detail)"
        case .malformedResponse(let detail):
            return "模型返回的内容不是合法 StyleSpec：\(detail)"
        case .cancelled:
            return "已取消"
        }
    }
}
