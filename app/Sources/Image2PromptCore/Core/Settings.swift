import Foundation
import Observation

/// 用户设置。非机密项走 UserDefaults，API key 走 Keychain。
@Observable
@MainActor
public final class Settings {
    public static let shared = Settings()

    private let defaults = UserDefaults.standard

    public var autoAnalyze: Bool {
        didSet { defaults.set(autoAnalyze, forKey: "autoAnalyze") }
    }

    public var maxConcurrent: Int {
        didSet { defaults.set(maxConcurrent, forKey: "maxConcurrent") }
    }

    public var providerID: String {
        didSet { defaults.set(providerID, forKey: "providerID") }
    }

    /// base_url 从第一天就存在，不是为了将来才加的：
    /// 接 OpenAI 兼容的国内模型（通义/智谱/豆包/Kimi/MiniMax）全靠它，
    /// 用中转的用户也需要它。只留一个 key 输入框的设计是不够的。
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
            "baseURL": "https://api.anthropic.com",
            "model": "claude-opus-5",
        ])
        autoAnalyze = defaults.bool(forKey: "autoAnalyze")
        maxConcurrent = defaults.integer(forKey: "maxConcurrent")
        providerID = defaults.string(forKey: "providerID") ?? "mock"
        baseURL = defaults.string(forKey: "baseURL") ?? "https://api.anthropic.com"
        model = defaults.string(forKey: "model") ?? "claude-opus-5"
        apiKey = Keychain.get("apiKey") ?? ""
    }

    /// 按当前设置造引擎。没配 key 时自动落回 Mock——
    /// 不填 key 也必须是完整可用的产品，不是残废版。
    public func makeProvider() -> any VisionProvider {
        switch providerID {
        case "anthropic" where !apiKey.isEmpty:
            return MockVisionProvider()  // A1 暂用 Mock，接真实 API 在后续里程碑
        default:
            return MockVisionProvider()
        }
    }
}
