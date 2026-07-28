import Image2PromptCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var settings = state.settings

        Form {
            Section("分析") {
                Toggle("拖入后自动分析", isOn: $settings.autoAnalyze)
                    .help("关掉后拖进来的图只入队，要手动点「开始分析」")

                Picker("同时分析", selection: $settings.maxConcurrent) {
                    ForEach([1, 2, 3, 5, 8], id: \.self) { n in
                        Text("\(n) 张").tag(n)
                    }
                }
            }

            Section("识图引擎") {
                Picker("引擎", selection: $settings.providerID) {
                    Text("Mock（假数据，不联网）").tag("mock")
                    Text("Anthropic").tag("anthropic")
                }

                if settings.providerID != "mock" {
                    TextField("Base URL", text: $settings.baseURL)
                        .textFieldStyle(.roundedBorder)
                    TextField("模型", text: $settings.model)
                        .textFieldStyle(.roundedBorder)
                    SecureField("API Key", text: $settings.apiKey)
                        .textFieldStyle(.roundedBorder)

                    Text(
                        "Key 存进 Keychain，不写进配置文件。\n"
                            + "Base URL 单独留字段是为了接 OpenAI 兼容的国内模型"
                            + "（通义 / 智谱 / 豆包 / Kimi / MiniMax），以及走中转的情况。"
                    )
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            if settings.providerID == "mock" {
                Section {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle").foregroundStyle(.secondary)
                        Text(
                            "当前用假数据跑体验路径：分析结果来自两份真图跑出来的 StyleSpec，"
                                + "不联网、不花钱。换成 Anthropic 需要 API key —— "
                                + "注意 API 与 Claude 订阅是分开计费的，订阅不含 API 额度。"
                        )
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 460)
        .onChange(of: settings.autoAnalyze) { _, _ in state.applySettings() }
        .onChange(of: settings.maxConcurrent) { _, _ in state.applySettings() }
        .onChange(of: settings.providerID) { _, _ in state.applySettings() }
    }
}
