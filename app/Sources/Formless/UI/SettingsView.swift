import AppKit
import FormlessCore
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            EngineTab()
                .tabItem { Label("识图引擎", systemImage: "eye") }
            AnalysisTab()
                .tabItem { Label("分析行为", systemImage: "slider.horizontal.3") }
            TasteLibraryTab()
                .tabItem { Label("审美库", systemImage: "heart.text.square") }
            DataTab()
                .tabItem { Label("数据", systemImage: "internaldrive") }
        }
        .frame(width: 560, height: 560)
    }
}

// MARK: - 识图引擎

private struct EngineTab: View {
    @Environment(AppState.self) private var state
    @State private var probeResult: String?
    @State private var probeOK = false

    var body: some View {
        @Bindable var settings = state.settings
        let status = settings.engineStatus

        Form {
            Section {
                StatusCard(status: status)
            }

            Section("算力从哪来") {
                Picker("引擎", selection: $settings.providerID) {
                    Text("Mock（假数据，不联网）").tag("mock")
                    ForEach(AgentPreset.builtins) { preset in
                        Text(preset.displayName).tag(preset.id)
                    }
                    Text("自定义 agent").tag("custom")
                    Text("Anthropic API").tag("anthropic")
                }

                if isAgent {
                    Note(
                        "**走你自己的 agent。** 用已有的订阅额度，不需要额外买 API。\n"
                            + "识图是这个工具最花钱的一环（全库几千张），走本地 agent 等于把贵的那半边降到零。")
                } else if settings.providerID == "anthropic" {
                    Note("**走 API，按量计费。** API 额度与 Claude 订阅是分开的——订阅不含 API 用量。")
                }
            }

            if settings.providerID == "custom" {
                Section("自定义 agent") {
                    TextField("可执行文件（命令名或绝对路径）", text: $settings.customExecutable)
                        .textFieldStyle(.roundedBorder)
                    TextField("参数模板", text: $settings.customArguments)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                    Toggle("指令走标准输入", isOn: $settings.customPromptViaStdin)
                    Note(
                        "`{{PROMPT}}` 会被替换成完整分析指令。指令有好几 KB，"
                            + "命令行支持从 stdin 读的话建议打开上面那个开关。\n"
                            + "任何「读一段指令、吐一段文字」的命令行都能接进来。")
                }
            }

            if settings.providerID == "anthropic" {
                Section("API 配置") {
                    TextField("Base URL", text: $settings.baseURL)
                        .textFieldStyle(.roundedBorder)
                    TextField("模型", text: $settings.model)
                        .textFieldStyle(.roundedBorder)
                    SecureField("API Key", text: $settings.apiKey)
                        .textFieldStyle(.roundedBorder)
                    Note(
                        "Key 存进 Keychain，不写配置文件。\n"
                            + "Base URL 单独留字段是为了接 OpenAI 兼容的国内模型"
                            + "（通义 / 智谱 / 豆包 / Kimi / MiniMax），以及走中转的情况。")
                }
            }

            if isAgent {
                Section("连通性") {
                    HStack {
                        Button("检测") { runProbe() }
                        if let probeResult {
                            Label(
                                probeResult,
                                systemImage: probeOK ? "checkmark.circle.fill" : "xmark.circle.fill"
                            )
                            .font(.system(size: 11))
                            .foregroundStyle(probeOK ? .green : .red)
                            .textSelection(.enabled)
                        }
                    }
                    Note(
                        "双击启动的 App 拿不到终端的 PATH，所以内置了常见安装位置的查找。"
                            + "还是找不到就填绝对路径。")
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings.providerID) { _, _ in probeResult = nil; state.applySettings() }
        .onChange(of: settings.customExecutable) { _, _ in probeResult = nil; state.applySettings() }
        .onChange(of: settings.customArguments) { _, _ in state.applySettings() }
        .onChange(of: settings.customPromptViaStdin) { _, _ in state.applySettings() }
    }

    private var isAgent: Bool {
        state.settings.providerID == "custom"
            || AgentPreset.builtins.contains { $0.id == state.settings.providerID }
    }

    private func runProbe() {
        switch state.settings.probeSelectedAgent() {
        case .success(let path):
            probeOK = true
            probeResult = path
        case .failure(let error):
            probeOK = false
            probeResult = error.localizedDescription
        }
    }
}

/// 一眼看清：现在谁在出算力、配没配好、能干什么不能干什么
private struct StatusCard: View {
    let status: EngineStatus

    private var tint: Color {
        switch status.level {
        case .ready: return .green
        case .degraded: return .orange
        case .broken: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: status.symbol)
                    .foregroundStyle(tint)
                Text(status.title)
                    .font(.system(size: 14, weight: .semibold))
            }

            Text(status.channel)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            if let detail = status.detail {
                Text(detail)
                    .font(.system(size: 10, design: status.level == .ready ? .monospaced : .default))
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider().padding(.vertical, 2)

            HStack(spacing: 16) {
                Capability(label: "识图", ok: status.canAnalyze)
                Capability(label: "生图", ok: status.canGenerate)
            }

            if !status.canGenerate {
                Text("agent 和视觉模型都只能看图，不能画图。生图要把提示词复制到即梦 / GPT Image 网页，或以后接生图 API。")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct Capability: View {
    let label: String
    let ok: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: ok ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(ok ? .green : .secondary)
            Text(label)
                .foregroundStyle(ok ? .primary : .secondary)
        }
        .font(.system(size: 11))
    }
}

// MARK: - 分析行为

private struct AnalysisTab: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var settings = state.settings

        Form {
            Section("入队之后") {
                Toggle("自动开始分析", isOn: $settings.autoAnalyze)
                Note("关掉后拖进来的图只入队，要手动点「开始分析」。想先挑一批再一起跑就关掉它。")
            }

            Section("并发与超时") {
                Picker("同时分析", selection: $settings.maxConcurrent) {
                    ForEach([1, 2, 3, 5, 8], id: \.self) { Text("\($0) 张").tag($0) }
                }
                Picker("单张超时", selection: $settings.agentTimeout) {
                    Text("2 分钟").tag(120.0)
                    Text("5 分钟").tag(300.0)
                    Text("10 分钟").tag(600.0)
                }
                Note(
                    "本地 agent 跑一份完整 StyleSpec 实测约 2~3 分钟。\n"
                        + "并发开太高会撞订阅的速率限制，3 路是稳妥起点。")
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings.autoAnalyze) { _, _ in state.applySettings() }
        .onChange(of: settings.maxConcurrent) { _, _ in state.applySettings() }
        .onChange(of: settings.agentTimeout) { _, _ in state.applySettings() }
    }
}

// MARK: - 审美库（Track B 占位）

private struct TasteLibraryTab: View {
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "hammer.fill").foregroundStyle(.orange)
                        Text("还没做").font(.system(size: 14, weight: .semibold))
                    }
                    Text("这里以后放你的个人审美偏好，让分析和生成结果逐渐贴近你的判断，而不是模型认为的「高级」。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }

            Section("会包含什么") {
                Row("偏好档案", "低饱和、不用金色和大理石、主体占比小于 40%、字体克制⋯⋯这类只属于你的判断")
                Row("调参盘默认值", "风格盘和色彩盘的起始位置，按你的习惯预设")
                Row("生成反馈", "标记「更像我的审美」/「不喜欢」，经验写回偏好而不污染原始 StyleSpec")
                Row("风格收藏板", "把跑出来的 StyleSpec 分组沉淀，下次直接调用")
            }

            Section {
                Note(
                    "这部分要等调参盘的规则在真图上验证过再落进来——"
                        + "先定好偏移轴怎么动，偏好才有东西可以调。\n"
                        + "在那之前留着这个位置，免得它被塞进别的地方。")
            }
        }
        .formStyle(.grouped)
    }

    private func Row(_ title: String, _ desc: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 12, weight: .medium))
            Text(desc)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 数据

private struct DataTab: View {
    @Environment(AppState.self) private var state
    @State private var confirmingClear = false

    var body: some View {
        Form {
            Section("本地库") {
                LabeledContent("条目") {
                    Text("\(state.queue.items.count) 张 · 已分析 \(state.queue.doneCount)")
                }
                if let path = state.storePath {
                    LabeledContent("位置") {
                        Text(path)
                            .font(.system(size: 10, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                    Button("在访达中显示") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                    }
                } else {
                    Label("数据库打不开，当前是内存模式，关掉就没了", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
                if let error = state.queue.lastStoreError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
            }

            Section("你的原图") {
                Note(
                    "**原图全程只读。** 库里只存路径，绝不复制、移动或改写你的图片文件。\n"
                        + "把图从原位置移走，这里会标记丢失，由你决定重新关联还是移除。")
            }

            Section {
                Button("清空本地库", role: .destructive) { confirmingClear = true }
                Note("只删索引和分析结果，不动你的原图。")
            }

            Section("关于") {
                LabeledContent("版本", value: "0.1.0（\(BuildInfo.milestone)）")
                LabeledContent("StyleSpec", value: "v\(BuildInfo.styleSpecVersion)")
            }
        }
        .formStyle(.grouped)
        .alert("清空本地库？", isPresented: $confirmingClear) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                state.selected = nil
                state.queue.clearAll()
            }
        } message: {
            Text("会删掉队列里全部 \(state.queue.items.count) 条记录和已分析出的 StyleSpec。你的原图不受影响。")
        }
    }
}

// MARK: - 复用

private struct Note: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle").foregroundStyle(.secondary)
            Text(.init(text))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
