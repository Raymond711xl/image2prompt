import Foundation

/// 一个本地 agent 命令行的调用方式。
///
/// 做成数据而不是写死代码，是因为 agent CLI 的参数会随版本变——
/// 用户能自己改，不用等 App 更新。同理，任何别的 agent（自建的、公司内部的）
/// 只要能"读一段指令、吐一段文字"，填个预设就能接进来。
public struct AgentPreset: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var displayName: String
    /// 可执行文件名或绝对路径。只给文件名时按 PATH 与常见安装位置查找。
    public var executable: String
    /// 参数模板。`{{PROMPT}}` 会被替换成完整分析指令。
    public var arguments: [String]
    /// true 则指令走 stdin，`arguments` 里不需要 `{{PROMPT}}`。
    /// 指令有好几 KB，走 stdin 比塞进 argv 稳妥。
    public var promptViaStdin: Bool
    /// 单张超时秒数
    public var timeout: TimeInterval

    public init(
        id: String,
        displayName: String,
        executable: String,
        arguments: [String],
        promptViaStdin: Bool = false,
        timeout: TimeInterval = 180
    ) {
        self.id = id
        self.displayName = displayName
        self.executable = executable
        self.arguments = arguments
        self.promptViaStdin = promptViaStdin
        self.timeout = timeout
    }

    // MARK: - 内置预设

    /// Claude Code。实测：单张约 12 秒，3 路并发仍约 12 秒。
    public static let claudeCode = AgentPreset(
        id: "claude-code",
        displayName: "Claude Code（claude CLI）",
        executable: "claude",
        arguments: ["-p", "{{PROMPT}}", "--allowed-tools", "Read", "--output-format", "text"],
        promptViaStdin: false
    )

    /// Codex。指令走 stdin：`codex exec` 在没有 PROMPT 参数时从标准输入读。
    public static let codex = AgentPreset(
        id: "codex",
        displayName: "Codex（codex CLI）",
        executable: "codex",
        arguments: ["exec", "-"],
        promptViaStdin: true
    )

    public static let builtins: [AgentPreset] = [claudeCode, codex]

    /// 自定义预设的起点
    public static let customTemplate = AgentPreset(
        id: "custom",
        displayName: "自定义 agent",
        executable: "",
        arguments: ["{{PROMPT}}"],
        promptViaStdin: false
    )

    func resolvedArguments(prompt: String) -> [String] {
        arguments.map { $0.replacingOccurrences(of: "{{PROMPT}}", with: prompt) }
    }
}
