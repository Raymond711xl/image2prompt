import Foundation
import Testing

@testable import FormlessCore

// MARK: - JSON 提取

@Test("从纯 JSON 里提取")
func extractsPlainJSON() throws {
    let data = try JSONExtractor.extract(from: #"{"a":1,"b":"x"}"#)
    let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(obj["a"] as? Int == 1)
}

@Test("从代码块围栏里提取")
func extractsFromCodeFence() throws {
    let raw = """
        好的，我来分析这张图。

        ```json
        {"medium":"photography","density":"sparse"}
        ```

        分析完成。
        """
    let data = try JSONExtractor.extract(from: raw)
    let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(obj["medium"] as? String == "photography")
}

@Test("嵌套对象的大括号能正确配对")
func handlesNestedBraces() throws {
    let raw = #"前言 {"outer":{"inner":{"deep":1}},"tail":2} 后记"#
    let data = try JSONExtractor.extract(from: raw)
    let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(obj["tail"] as? Int == 2)
    #expect(obj["outer"] != nil)
}

@Test("字符串里的大括号不影响配对")
func ignoresBracesInsideStrings() throws {
    // 风格 DNA 里完全可能出现花括号或转义引号，正则会在这里翻车
    let raw = #"{"style_dna":"包含 } 和 { 的描述，还有\"引号\"","ok":true}"#
    let data = try JSONExtractor.extract(from: raw)
    let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(obj["ok"] as? Bool == true)
    #expect((obj["style_dna"] as? String)?.contains("}") == true)
}

@Test("正文里偶然的花括号会被跳过，取到真正的 JSON")
func skipsNonJSONBraces() throws {
    let raw = "模板语法 {{PROMPT}} 只是文本，真正的结果是 {\"real\":true}"
    let data = try JSONExtractor.extract(from: raw)
    let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(obj["real"] as? Bool == true)
}

@Test("没有 JSON 时报错并带上原文末尾")
func throwsWhenNoJSON() {
    #expect(throws: JSONExtractor.ExtractError.self) {
        _ = try JSONExtractor.extract(from: "我读不到这张图片，路径不存在。")
    }
}

// MARK: - 可执行文件查找

@Test("绝对路径直接解析")
func resolvesAbsolutePath() throws {
    let url = try AgentRunner.resolveExecutable("/bin/echo")
    #expect(url.path == "/bin/echo")
}

@Test("裸命令名能在常见位置找到")
func resolvesBareName() throws {
    let url = try AgentRunner.resolveExecutable("echo")
    #expect(FileManager.default.isExecutableFile(atPath: url.path))
}

@Test("找不到时报错")
func throwsOnMissingExecutable() {
    #expect(throws: AgentRunner.AgentError.self) {
        _ = try AgentRunner.resolveExecutable("definitely-not-a-real-binary-xyz")
    }
}

@Test("搜索路径覆盖 GUI 启动时缺失的常见安装位置")
func searchPathsCoverGUIGap() {
    // GUI 启动的 App 只有 /usr/bin:/bin:/usr/sbin:/sbin，
    // agent 常装在 npm-global 或 homebrew 下，必须自己补上
    #expect(AgentRunner.searchPaths.contains { $0.hasSuffix("/.npm-global/bin") })
    #expect(AgentRunner.searchPaths.contains("/opt/homebrew/bin"))
    #expect(AgentRunner.searchPaths.contains("/usr/local/bin"))
}

// MARK: - 进程执行

@Test("能跑起子进程并拿回标准输出")
func runsProcessAndCapturesOutput() async throws {
    let preset = AgentPreset(
        id: "test", displayName: "echo", executable: "/bin/echo",
        arguments: ["{{PROMPT}}"], timeout: 10)
    let out = try await AgentRunner.run(preset: preset, prompt: "hello world")
    #expect(out.trimmingCharacters(in: .whitespacesAndNewlines) == "hello world")
}

@Test("指令能走 stdin")
func passesPromptViaStdin() async throws {
    let preset = AgentPreset(
        id: "test", displayName: "cat", executable: "/bin/cat",
        arguments: [], promptViaStdin: true, timeout: 10)
    let out = try await AgentRunner.run(preset: preset, prompt: "from stdin")
    #expect(out.trimmingCharacters(in: .whitespacesAndNewlines) == "from stdin")
}

@Test("非零退出码带回 stderr")
func reportsNonZeroExit() async {
    let preset = AgentPreset(
        id: "test", displayName: "sh", executable: "/bin/sh",
        arguments: ["-c", "echo boom >&2; exit 3"], timeout: 10)
    await #expect(throws: AgentRunner.AgentError.self) {
        _ = try await AgentRunner.run(preset: preset, prompt: "")
    }
}

@Test("超时会中止进程")
func timesOut() async {
    let preset = AgentPreset(
        id: "test", displayName: "sleep", executable: "/bin/sleep",
        arguments: ["30"], timeout: 0.5)
    let start = Date()
    await #expect(throws: AgentRunner.AgentError.self) {
        _ = try await AgentRunner.run(preset: preset, prompt: "")
    }
    #expect(Date().timeIntervalSince(start) < 5, "超时没有真的中止进程")
}

// MARK: - 分析指令

@Test("分析指令能填好图片路径和 schema 路径")
func buildsAnalyzePrompt() throws {
    let prompt = try AnalyzePrompt.build(imageURL: URL(fileURLWithPath: "/tmp/demo.jpg"))
    #expect(prompt.contains("/tmp/demo.jpg"))
    #expect(prompt.contains("stylespec.v0.1.json"))
    #expect(prompt.contains("{{IMAGE_PATH}}") == false, "占位符没替换干净")
    #expect(prompt.contains("{{SCHEMA_PATH}}") == false, "占位符没替换干净")
}

@Test("schema 随包分发，agent 能直接读到")
func schemaIsBundled() throws {
    let url = try AnalyzePrompt.schemaURL()
    #expect(FileManager.default.isReadableFile(atPath: url.path))
}

@Test("读不到图片时不启动 agent，直接报错")
func rejectsUnreadableImage() async {
    let provider = LocalAgentProvider(preset: .claudeCode)
    await #expect(throws: VisionError.self) {
        _ = try await provider.analyze(imageURL: URL(fileURLWithPath: "/tmp/does-not-exist-xyz.jpg"))
    }
}

@Test("内置预设齐全")
func builtinPresets() {
    #expect(AgentPreset.builtins.contains { $0.id == "claude-code" })
    #expect(AgentPreset.builtins.contains { $0.id == "codex" })
    // Codex 走 stdin：指令有好几 KB，塞 argv 不稳
    #expect(AgentPreset.codex.promptViaStdin)
}
