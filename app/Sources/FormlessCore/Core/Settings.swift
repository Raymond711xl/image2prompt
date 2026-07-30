import Foundation
import Observation

/// 用户设置。非机密项走 UserDefaults，API key 走 Keychain。
@Observable
@MainActor
public final class Settings {
    public static let shared = Settings()

    private let defaults = UserDefaults.standard

    // MARK: - 分析行为

    public var autoAnalyze: Bool {
        didSet { defaults.set(autoAnalyze, forKey: "autoAnalyze") }
    }

    public var maxConcurrent: Int {
        didSet { defaults.set(maxConcurrent, forKey: "maxConcurrent") }
    }

    // MARK: - 识图引擎

    /// `mock` / 内置 agent 预设 id / `custom` / `anthropic`
    public var providerID: String {
        didSet { defaults.set(providerID, forKey: "providerID") }
    }

    // MARK: - 自定义 agent

    /// 任何"读一段指令、吐一段文字"的命令行都能接进来——
    /// 自建 agent、公司内部 agent、别的 CLI，填三个字段就行。
    public var customExecutable: String {
        didSet { defaults.set(customExecutable, forKey: "customExecutable") }
    }

    /// 空格分隔的参数模板，`{{PROMPT}}` 会被替换成完整分析指令
    public var customArguments: String {
        didSet { defaults.set(customArguments, forKey: "customArguments") }
    }

    public var customPromptViaStdin: Bool {
        didSet { defaults.set(customPromptViaStdin, forKey: "customPromptViaStdin") }
    }

    /// 单张超时秒数。本地 agent 跑一份完整 StyleSpec 实测约 2~3 分钟，默认给足。
    public var agentTimeout: Double {
        didSet { defaults.set(agentTimeout, forKey: "agentTimeout") }
    }

    // MARK: - API

    /// base_url 从第一天就存在：接 OpenAI 兼容的国内模型
    /// （通义/智谱/豆包/Kimi/MiniMax）全靠它，走中转的用户也需要。
    public var baseURL: String {
        didSet { defaults.set(baseURL, forKey: "baseURL") }
    }

    public var model: String {
        didSet { defaults.set(model, forKey: "model") }
    }

    public var apiKey: String {
        didSet { Keychain.set(apiKey, for: "apiKey") }
    }

    private init() {
        defaults.register(defaults: [
            "autoAnalyze": true,
            "maxConcurrent": 3,
            "providerID": "mock",
            "customExecutable": "",
            "customArguments": "{{PROMPT}}",
            "customPromptViaStdin": false,
            "agentTimeout": 300.0,
            "baseURL": "https://api.anthropic.com",
            "model": "claude-opus-5",
        ])
        autoAnalyze = defaults.bool(forKey: "autoAnalyze")
        maxConcurrent = defaults.integer(forKey: "maxConcurrent")
        providerID = defaults.string(forKey: "providerID") ?? "mock"
        customExecutable = defaults.string(forKey: "customExecutable") ?? ""
        customArguments = defaults.string(forKey: "customArguments") ?? "{{PROMPT}}"
        customPromptViaStdin = defaults.bool(forKey: "customPromptViaStdin")
        agentTimeout = defaults.double(forKey: "agentTimeout")
        baseURL = defaults.string(forKey: "baseURL") ?? "https://api.anthropic.com"
        model = defaults.string(forKey: "model") ?? "claude-opus-5"
        apiKey = Keychain.get("apiKey") ?? ""

        // 首次启动扫一遍本机装了哪个 agent，装了就直接用它。
        //
        // Mock 是兜底，不该是大多数人第一次打开时看到的东西：装过 Claude Code 或 Codex
        // 的人零配置就能真的干活，什么都没装的人才落回 Mock——"不填任何东西也是完整可用
        // 的产品"这条原则不变，只是把"可用"从假数据升级成真分析。
        //
        // 只跑一次，用单独的标记位记住。之后用户显式选了什么就是什么，包括显式选回 Mock。
        // 不能用 providerID 有没有值来判断：register(defaults:) 注册的兜底值，
        // object(forKey:) 一样读得到，区分不出"没设过"和"设成了 mock"。
        if !defaults.bool(forKey: "engineAutoDetected") {
            defaults.set(true, forKey: "engineAutoDetected")
            if let found = Self.detectInstalledAgent() {
                providerID = found
                // init 里的赋值不触发 didSet，得自己落盘
                defaults.set(found, forKey: "providerID")
            }
        }
    }

    /// 按内置预设的顺序找第一个真的装了的 agent。都找不到返回 nil，保持 Mock。
    private static func detectInstalledAgent() -> String? {
        AgentPreset.builtins.first { preset in
            (try? AgentRunner.resolveExecutable(preset.executable)) != nil
        }?.id
    }

    // MARK: - 组装引擎

    /// 当前选中的 agent 预设（选的不是 agent 时为 nil）
    public var selectedPreset: AgentPreset? {
        if providerID == "custom" {
            var preset = AgentPreset.customTemplate
            preset.executable = customExecutable
            preset.arguments = customArguments
                .split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            preset.promptViaStdin = customPromptViaStdin
            preset.timeout = agentTimeout
            return preset
        }
        guard var preset = AgentPreset.builtins.first(where: { $0.id == providerID }) else {
            return nil
        }
        preset.timeout = agentTimeout
        return preset
    }

    /// 按当前设置造引擎。配置不完整时落回 Mock——
    /// 不填任何东西也必须是完整可用的产品，不是残废版。
    public func makeProvider() -> any VisionProvider {
        if let preset = selectedPreset, !preset.executable.isEmpty {
            return LocalAgentProvider(preset: preset)
        }
        // API 引擎待接入；在那之前选了 anthropic 也先走 Mock
        return MockVisionProvider()
    }

    /// 设置界面用来做连通性自检
    public func probeSelectedAgent() -> Result<String, Error> {
        guard let preset = selectedPreset, !preset.executable.isEmpty else {
            return .failure(
                AgentRunner.AgentError.executableNotFound(customExecutable.isEmpty ? "（未填）" : customExecutable))
        }
        do {
            let url = try AgentRunner.resolveExecutable(preset.executable)
            return .success(url.path)
        } catch {
            return .failure(error)
        }
    }
}
