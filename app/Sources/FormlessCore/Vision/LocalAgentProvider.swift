import Foundation

/// 用本地已装的 agent CLI 完成识图。
///
/// 为什么这条路值得做：识图是整个产品最花钱的一环（全库几千张），而生图是零头。
/// 走本地 agent 把贵的那半边成本降到零——用户已经付过订阅了，不必再买 API。
///
/// 对分发也是加分项：装了 Claude Code 或 Codex 的人零配置就能用；没装的人再填 API key。
///
/// 两个限制要清楚：
/// 1. **agent 不能生图**。Claude Code / Codex 都是文本+代码 agent，能看图不能画图。
///    生图仍需生图模型 API，或手动贴到网页。
/// 2. **与 App Store 沙盒互斥**。沙盒禁止启动任意子进程，上架就用不了这个模式。
///    直接分发（公证的 .dmg）不受影响。
public struct LocalAgentProvider: VisionProvider {
    public let preset: AgentPreset

    public var id: String { "local-agent:\(preset.id)" }
    public var displayName: String { preset.displayName }
    public var requiresAPIKey: Bool { false }

    public init(preset: AgentPreset) {
        self.preset = preset
    }

    public func analyze(imageURL: URL) async throws -> StyleSpec {
        guard FileManager.default.isReadableFile(atPath: imageURL.path) else {
            throw VisionError.unreadableImage(imageURL)
        }

        let prompt = try AnalyzePrompt.build(imageURL: imageURL)
        let output: String
        do {
            output = try await AgentRunner.run(preset: preset, prompt: prompt)
        } catch let error as AgentRunner.AgentError {
            throw VisionError.agentFailed(error.errorDescription ?? "\(error)")
        }

        if Task.isCancelled { throw VisionError.cancelled }

        let json: Data
        do {
            json = try JSONExtractor.extract(from: output)
        } catch {
            throw VisionError.malformedResponse(error.localizedDescription)
        }

        do {
            return try StyleSpec.decode(from: json)
        } catch let error as DecodingError {
            throw VisionError.malformedResponse(Self.describe(error))
        }
    }

    /// 解码失败要说清楚是哪个字段——agent 最常见的错是枚举值写了 schema 之外的取值，
    /// 报"数据损坏"帮不上忙，报"medium 不接受 product_photo"才能改指令。
    static func describe(_ error: DecodingError) -> String {
        func path(_ context: DecodingError.Context) -> String {
            context.codingPath.map(\.stringValue).joined(separator: ".")
        }
        switch error {
        case .keyNotFound(let key, let context):
            let parent = path(context)
            return "缺少必填字段 \(parent.isEmpty ? key.stringValue : "\(parent).\(key.stringValue)")"
        case .typeMismatch(let type, let context):
            return "字段 \(path(context)) 类型不对，期望 \(type)"
        case .valueNotFound(let type, let context):
            return "字段 \(path(context)) 为空，期望 \(type)"
        case .dataCorrupted(let context):
            let where_ = path(context)
            return where_.isEmpty
                ? "JSON 结构不合法：\(context.debugDescription)"
                : "字段 \(where_) 取值不在 schema 允许的枚举里"
        @unknown default:
            return error.localizedDescription
        }
    }
}
