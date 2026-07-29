import Image2PromptCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var state
    @State private var probe: String?
    @State private var probeOK = false

    var body: some View {
        @Bindable var settings = state.settings

        Form {
            Section("分析") {
                Toggle("拖入后自动分析", isOn: $settings.autoAnalyze)
                    .help("关掉后拖进来的图只入队，要手动点「开始分析」")

                Picker("同时分析", selection: $settings.maxConcurrent) {
                    ForEach([1, 2, 3, 5, 8], id: \.self) { Text("\($0) 张").tag($0) }
                }
            }

            Section("识图引擎") {
                Picker("引擎", selection: $settings.providerID) {
                    Text("Mock（假数据，不联网）").tag("mock")
                    Divider()
                    ForEach(AgentPreset.builtins) { preset in
                        Text(preset.displayName).tag(preset.id)
                    }
                    Text("自定义 agent").tag("custom")
                    Divider()
                    Text("Anthropic API（待接入）").tag("anthropic")
                }

                if settings.providerID == "custom" {
                    TextField("可执行文件（命令名或绝对路径）", text: $settings.customExecutable)
                        .textFieldStyle(.roundedBorder)
                    TextField("参数模板", text: $settings.customArguments)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                    Toggle("指令走标准输入", isOn: $settings.customPromptViaStdin)
                    Note(
                        "`{{PROMPT}}` 会被替换成完整分析指令。指令有好几 KB，"
                            + "命令行支持从 stdin 读的话建议打开上面那个开关。")
                }

                if isAgent {
                    HStack {
                        Picker("单张超时", selection: $settings.agentTimeout) {
                            Text("2 分钟").tag(120.0)
                            Text("5 分钟").tag(300.0)
                            Text("10 分钟").tag(600.0)
                        }
                        Button("检测") { runProbe() }
                    }
                    if let probe {
                        Label(probe, systemImage: probeOK ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(probeOK ? .green : .red)
                    }
                }

                if settings.providerID == "anthropic" {
                    TextField("Base URL", text: $settings.baseURL)
                        .textFieldStyle(.roundedBorder)
                    TextField("模型", text: $settings.model)
                        .textFieldStyle(.roundedBorder)
                    SecureField("API Key", text: $settings.apiKey)
                        .textFieldStyle(.roundedBorder)
                    Note(
                        "Key 存 Keychain，不写进配置文件。Base URL 单独留字段是为了接"
                            + "OpenAI 兼容的国内模型（通义 / 智谱 / 豆包 / Kimi / MiniMax）。\n"
                            + "这条路还没接通，选它目前仍走 Mock。")
                }
            }

            Section {
                switch settings.providerID {
                case "mock":
                    Note(
                        "当前用假数据跑体验路径：结果来自两份真图跑出来的 StyleSpec，"
                            + "不联网、不花钱。要看真实结果，上面换成你已装的 agent。")
                case "custom", "claude-code", "codex":
                    Note(
                        "走本地 agent：用你已有的订阅额度，不需要额外买 API。\n"
                            + "两点要知道——agent 只能看图不能生图，生图仍需复制提示词到网页或接生图 API；"
                            + "另外这个模式依赖启动子进程，与 Mac App Store 的沙盒不兼容。")
                default:
                    EmptyView()
                }
            }

            Section("数据") {
                LabeledContent("本地库") {
                    Text(state.storePath ?? "内存模式（未落盘）")
                        .font(.system(size: 10, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                if let error = state.queue.lastStoreError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
                Note("原图全程只读——库里只存路径，绝不复制、移动或改写你的图片。")
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520)
        .onChange(of: settings.autoAnalyze) { _, _ in state.applySettings() }
        .onChange(of: settings.maxConcurrent) { _, _ in state.applySettings() }
        .onChange(of: settings.providerID) { _, _ in probe = nil; state.applySettings() }
        .onChange(of: settings.customExecutable) { _, _ in probe = nil; state.applySettings() }
        .onChange(of: settings.customArguments) { _, _ in state.applySettings() }
        .onChange(of: settings.customPromptViaStdin) { _, _ in state.applySettings() }
        .onChange(of: settings.agentTimeout) { _, _ in state.applySettings() }
    }

    private var isAgent: Bool {
        state.settings.providerID == "custom"
            || AgentPreset.builtins.contains { $0.id == state.settings.providerID }
    }

    private func runProbe() {
        switch state.settings.probeSelectedAgent() {
        case .success(let path):
            probeOK = true
            probe = "找到了：\(path)"
        case .failure(let error):
            probeOK = false
            probe = error.localizedDescription
        }
    }
}

private struct Note: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle").foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
