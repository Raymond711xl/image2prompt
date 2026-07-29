import Foundation

/// 分析指令：把 SKILL.md 模式 A 的方法论编成一份会产出合法 StyleSpec 的指令。
///
/// 它是**所有** VisionProvider 的共同输入——本地 agent 收到的是它，
/// 以后接 API 时它就是系统提示词。规则只有一份，换引擎不换方法论。
public enum AnalyzePrompt {

    public enum PromptError: Error, LocalizedError {
        case missingResource(String)

        public var errorDescription: String? {
            switch self {
            case .missingResource(let name):
                return "打包里找不到资源：\(name)"
            }
        }
    }

    /// schema 随 .app 一起分发，agent 用得到的是这个真实磁盘路径
    public static func schemaURL() throws -> URL {
        guard let url = Bundle.module.url(forResource: "stylespec.v0.1", withExtension: "json")
        else {
            throw PromptError.missingResource("stylespec.v0.1.json")
        }
        return url
    }

    public static func template() throws -> String {
        guard let url = Bundle.module.url(forResource: "analyze-prompt", withExtension: "md") else {
            throw PromptError.missingResource("analyze-prompt.md")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// 填好图片路径和 schema 路径的完整指令
    public static func build(imageURL: URL) throws -> String {
        try template()
            .replacingOccurrences(of: "{{IMAGE_PATH}}", with: imageURL.path)
            .replacingOccurrences(of: "{{SCHEMA_PATH}}", with: try schemaURL().path)
    }
}
