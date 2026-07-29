import Foundation

/// 当前识图引擎处于什么状态，用一句话说清"谁在出算力、花不花钱、配没配好"。
///
/// 做成 Core 里的模型而不是散在界面里，是因为这几句话的正确性很重要——
/// 用户据此判断要不要去买 API。写错了会让人白花钱，所以它要能被测试。
public struct EngineStatus: Sendable, Equatable {
    public enum Level: Sendable {
        /// 配好了，可以真的干活
        case ready
        /// 能跑，但不是真实分析（Mock），或配置不完整会落回 Mock
        case degraded
        /// 配了但找不到，跑不起来
        case broken
    }

    public var level: Level
    /// 引擎名，如「Claude Code」
    public var title: String
    /// 算力从哪来、怎么计费
    public var channel: String
    /// 补充信息：可执行文件路径，或错误原因
    public var detail: String?
    /// 能不能识图
    public var canAnalyze: Bool
    /// 能不能生图。目前**全部为 false**——agent 和视觉 API 都只能看图不能画图。
    public var canGenerate: Bool

    public var symbol: String {
        switch level {
        case .ready: return "checkmark.circle.fill"
        case .degraded: return "exclamationmark.triangle.fill"
        case .broken: return "xmark.circle.fill"
        }
    }
}

extension Settings {

    /// 当前引擎的真实状态。**以实际能不能跑为准，不是以用户选了什么为准**——
    /// 选了 Anthropic 但没填 key，这里就要说清楚"实际还是走 Mock"。
    public var engineStatus: EngineStatus {
        switch providerID {
        case "mock":
            return EngineStatus(
                level: .degraded,
                title: "Mock（假数据）",
                channel: "不联网、不花钱",
                detail: "结果来自两份预置样本，与你拖进来的图无关。仅用于试用界面。",
                canAnalyze: false,
                canGenerate: false)

        case "anthropic":
            let hasKey = !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
            return EngineStatus(
                level: hasKey ? .ready : .degraded,
                title: "Anthropic API",
                channel: hasKey ? "按量计费，走你的 API 额度" : "未填 API Key",
                detail: hasKey
                    ? "\(model) · \(baseURL)"
                    : "这条路还没接通，当前实际仍走 Mock。",
                canAnalyze: false,
                canGenerate: false)

        default:
            guard let preset = selectedPreset else {
                return EngineStatus(
                    level: .broken, title: "未知引擎", channel: "配置无效",
                    detail: "选中的引擎 \(providerID) 不存在", canAnalyze: false, canGenerate: false)
            }
            if preset.executable.trimmingCharacters(in: .whitespaces).isEmpty {
                return EngineStatus(
                    level: .degraded,
                    title: preset.displayName,
                    channel: "还没填可执行文件",
                    detail: "填好之前实际仍走 Mock。",
                    canAnalyze: false,
                    canGenerate: false)
            }
            switch probeSelectedAgent() {
            case .success(let path):
                return EngineStatus(
                    level: .ready,
                    title: preset.displayName,
                    channel: "本地 agent · 用你已有的订阅额度，不额外计费",
                    detail: path,
                    canAnalyze: true,
                    canGenerate: false)
            case .failure(let error):
                return EngineStatus(
                    level: .broken,
                    title: preset.displayName,
                    channel: "本地 agent · 找不到可执行文件",
                    detail: error.localizedDescription,
                    canAnalyze: false,
                    canGenerate: false)
            }
        }
    }
}
