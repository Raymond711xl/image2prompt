import AppKit
import FormlessCore
import SwiftUI

/// Brief 输入区：先自由写，再把解析结果摊开给你改。
///
/// 不做细粒度表单是刻意的——上来就填十个字段会打断思路，而且很多时候脑子里
/// 本来就是一句综合描述。但解析一定会错，所以结果必须可编辑。
struct BriefSection: View {
    @Bindable var item: QueueItem
    let spec: StyleSpec
    /// Brief 改动后落库。原文和解析结果都要存——解析可能出错，原文是唯一真相。
    var onBriefChanged: (() -> Void)?

    @State private var compiled: [(model: ModelId, result: Result<CompiledPrompt, CompileError>)] =
        []
    @State private var parsing = false
    @State private var parseError: String?
    @State private var parsedByModel = false
    @State private var history: [(record: GenerationStore.Record, imageURL: URL)] = []

    /// 生成状态住在 AppState 里，不是这个视图的 @State。
    ///
    /// 原来是 `@State generatingModel`，有两个毛病：侧栏读不到（只有当前选中的
    /// 那张图知道自己在跑，进度条无从画起），而且 SwiftUI 会复用这个视图，
    /// 切到另一张图时那个 @State 跟着串台，别的图也显示"生成中"。
    @Environment(AppState.self) private var state

    private var genState: GenerationQueue.State { state.generation.state(for: item.id) }

    private var generatingModel: ModelId? {
        if case .running(let model, _) = genState { return model }
        return nil
    }

    private var generationError: String? {
        if case .failed(let message) = genState { return message }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            InputCard(
                item: item,
                parsing: parsing,
                error: parseError,
                usesModel: Settings.shared.briefParserIsModel,
                onParse: { parseBrief() },
                onClear: {
                    item.brief = nil
                    parseError = nil
                    compile()
                    onBriefChanged?()
                },
                onChanged: { onBriefChanged?() })

            if let brief = item.brief {
                let binding = Binding(
                    get: { brief },
                    set: {
                        item.brief = $0
                        compile()
                        onBriefChanged?()
                    })

                // 文案独立成一块：它是这次输入里**最确定**的东西（用户心里就是那几个字），
                // 不该和"主体是什么、什么调子"这种要 AI 揣摩的内容混在一个框里等解析。
                CopyCard(brief: binding)
                ParsedCard(brief: binding, isModelParsed: parsedByModel)

                ForEach(compiled, id: \.model) { entry in
                    PromptCard(
                        model: entry.model,
                        result: entry.result,
                        canGenerate: state.generation.isAvailable,
                        isGenerating: generatingModel == entry.model,
                        // 一次只跑一个，而且是全局的：并发生图只会同时烧额度，
                        // 而判断"像不像"本来就得一张一张看。
                        isBusy: state.generation.isBusy,
                        onGenerate: { generate(model: entry.model, prompt: $0) }
                    )
                }

                GenerationsCard(
                    history: history,
                    startedAt: genState.startedAt,
                    error: generationError,
                    providerName: state.generation.providerName,
                    onDelete: { jobID in
                        GenerationStore.delete(jobID: jobID, for: item.id)
                        history = GenerationStore.history(for: item.id)
                    }
                )
            }
        }
        .onAppear {
            if item.brief != nil { compile() }
            history = GenerationStore.history(for: item.id)
        }
        .onChange(of: item.id) { _, _ in
            compiled = []
            history = GenerationStore.history(for: item.id)
        }
        // 生成完成后重读历史。用队列的计数器而不是回调：详情页会被反复重建，
        // 回调容易在重建时挂丢，计数器是状态，重建后照样能比对。
        .onChange(of: state.generation.completionTick) { _, _ in
            history = GenerationStore.history(for: item.id)
        }
    }

    /// 解析这段话。有本地 agent 就走 AI 读全文，没有才退回正则。
    private func parseBrief() {
        let text = item.briefText
        let parser = Settings.shared.makeBriefParser()
        parsing = true
        parseError = nil

        Task {
            defer { parsing = false }
            do {
                item.brief = try await parser.parse(text: text, spec: spec)
                parsedByModel = parser is ModelBriefParser
            } catch {
                // AI 解析失败不该让人卡住：退回正则，但要如实说明降级了。
                item.brief = ModelBriefParser.fallback(text: text, spec: spec)
                parsedByModel = false
                parseError = "AI 解析失败，已退回正则粗解析：\(error.localizedDescription)"
            }
            compile()
            onBriefChanged?()
        }
    }

    private func compile() {
        guard let brief = item.brief else {
            compiled = []
            return
        }
        compiled = Compiler.compileAll(spec, brief)
    }

    /// 只负责发起。跑、落库、发提示音都在 GenerationQueue 里——
    /// 那些事在视图关掉之后也得继续，不能挂在视图的生命周期上。
    private func generate(model: ModelId, prompt: String) {
        guard let brief = item.brief else { return }
        state.generation.generate(
            itemID: item.id, model: model, prompt: prompt, aspectRatio: brief.aspectRatio)
    }
}

// MARK: - 自由文本输入

private struct InputCard: View {
    @Bindable var item: QueueItem
    let parsing: Bool
    let error: String?
    /// 解析走的是 AI 还是正则兜底。必须如实告诉用户——
    /// 两者的吃全率差得远，用户得知道自己在跟哪一个说话。
    let usesModel: Bool
    let onParse: () -> Void
    let onClear: () -> Void
    let onChanged: () -> Void

    private var isEmpty: Bool {
        item.briefText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        SectionCard(
            title: "这次要生成什么",
            subtitle: usesModel
                ? "整段写，AI 会读全文——想到什么写什么，主体、细节、调子、忌讳都行"
                : "整段写。当前没有可用的本地 agent，只能做正则粗解析，会漏"
        ) {
            TextEditor(text: $item.briefText)
                .font(.system(size: 12))
                .frame(minHeight: 96)
                .padding(6)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
                .overlay(alignment: .topLeading) {
                    if item.briefText.isEmpty {
                        Text(
                            "例：用这个风格做一张小红书封面，主体换成一枚中国邮政的老邮票，\n"
                                + "票面是天安门，要有齿孔边缘，整体偏怀旧一点、别太亮。\n"
                                + "右下角留一块空白给二维码，不要人物，不要现代元素"
                        )
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                    }
                }

            HStack(spacing: 10) {
                Button {
                    onParse()
                } label: {
                    if parsing {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("AI 读取中…")
                        }
                    } else {
                        Text(usesModel ? "让 AI 读一遍" : "解析")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isEmpty || parsing)

                if item.brief != nil && !parsing {
                    Button("清空", action: onClear).buttonStyle(.borderless)
                }

                Spacer()

                Text(usesModel ? "写的每一条都会有归宿" : "只认几个固定句式，其余会丢")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            if let error {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onChange(of: item.briefText) { _, _ in onChanged() }
    }
}

// MARK: - 画面文字

/// 文案单独一块。
///
/// 和自由描述分开，是因为这两类信息的确定性完全不同：文案是用户心里就定死的那几个字，
/// 一个字都不能错；而"什么主体、什么调子"是要 AI 揣摩的。混在一个框里让 AI 猜哪几个字
/// 是文案，本来就是没必要的风险。
private struct CopyCard: View {
    @Binding var brief: Brief

    private var copy: CopyBlock { brief.copy ?? CopyBlock() }

    private func bind(_ keyPath: WritableKeyPath<CopyBlock, String?>) -> Binding<String> {
        Binding(
            get: { copy[keyPath: keyPath] ?? "" },
            set: {
                var c = copy
                c[keyPath: keyPath] = $0.isEmpty ? nil : $0
                brief.copy = c.isEmpty ? nil : c
            })
    }

    var body: some View {
        SectionCard(title: "画面文字", subtitle: "要出现在图上的字，逐字填。不需要就留空") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Label2("标题")
                    TextField("如 见字如面", text: bind(\.title)).textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Label2("副标题")
                    TextField("可空", text: bind(\.subtitle)).textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Label2("正文小字")
                    TextField("可空", text: bind(\.body)).textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Label2("留在哪")
                    Picker(
                        "",
                        selection: Binding(
                            get: { brief.copySafeArea ?? "none" },
                            set: { brief.copySafeArea = $0 })
                    ) {
                        ForEach(Self.areas, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    .labelsHidden()
                }
            }

            Toggle(
                "让模型直接把文字画进图里",
                isOn: Binding(
                    get: { brief.renderTextInImage ?? false },
                    set: { brief.renderTextInImage = $0 })
            )
            .font(.system(size: 12))
            .padding(.top, 4)

            Text(
                (brief.renderTextInImage ?? false)
                    ? "模型画字容易缺笔画、串行。中文尤其。"
                    : "关闭时只让模型把那块位置留干净，文字后期以可编辑图层叠上去——正确性和排版更可控。"
            )
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private static let areas: [(String, String)] = [
        ("none", "不特别留"),
        ("top_third", "上三分之一"),
        ("bottom_third", "下三分之一"),
        ("center", "中部"),
        ("left_half", "左半"),
        ("right_half", "右半"),
        ("upper_left", "左上"),
        ("upper_right", "右上"),
        ("lower_left", "左下"),
        ("lower_right", "右下"),
    ]
}

// MARK: - 可编辑的解析结果

/// 解析结果。**默认折叠。**
///
/// 用户的原话："解析其实没什么用，拆得太细了。" 症结不在字段多，在于把一堆中间态
/// 摊在主路径上——真正该看的是"AI 理解成了什么"和"最终提示词长什么样"。
/// 所以这里只留一行摘要，想改的人再展开。字段一个没删。
private struct ParsedCard: View {
    @Binding var brief: Brief
    let isModelParsed: Bool

    @State private var expanded = false

    /// 一行话复述 AI 的理解。看这一行就能判断解析对不对，不用逐字段核。
    private var summary: String {
        var bits: [String] = []
        let subject = [brief.subject, brief.subjectDetail]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "，")
        if !subject.isEmpty { bits.append(subject) }
        if let action = brief.action, !action.isEmpty { bits.append(action) }
        if let scene = brief.scene, !scene.isEmpty { bits.append(scene) }
        if let avoid = brief.mustAvoid, !avoid.isEmpty {
            bits.append("不要\(avoid.joined(separator: "、"))")
        }
        if let keep = brief.mustKeep, !keep.isEmpty {
            bits.append("保留\(keep.joined(separator: "、"))")
        }
        return bits.isEmpty ? "（什么都没解析出来）" : bits.joined(separator: "；")
    }

    var body: some View {
        SectionCard(title: nil, subtitle: nil) {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: isModelParsed ? "sparkles" : "textformat.abc")
                    .font(.system(size: 10))
                    .foregroundStyle(isModelParsed ? Color.accentColor : .secondary)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(isModelParsed ? "AI 理解成了" : "正则解析出（会漏，建议展开核对）")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(summary)
                        .font(.system(size: 12))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button(expanded ? "收起" : "展开改") {
                    withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
                }
                .font(.system(size: 11))
                .buttonStyle(.borderless)
            }

            if expanded {
                Divider().padding(.vertical, 6)
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Label2("主体")
                        TextField("这次要画什么", text: $brief.subject)
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Label2("细节")
                        TextField("外观、材质、颜色、构成", text: optional(\.subjectDetail))
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Label2("动作")
                        TextField("主体在做什么（可空）", text: optional(\.action))
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Label2("场景 / 调子")
                        TextField("环境、氛围、整体感觉", text: optional(\.scene))
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Label2("用途")
                        Picker("", selection: $brief.purpose) {
                            ForEach(Array(Vocab.purposeCN.keys).sorted(), id: \.self) { key in
                                Text(Vocab.purposeCN[key] ?? key).tag(key)
                            }
                        }
                        .labelsHidden()
                    }
                    GridRow {
                        Label2("画幅")
                        TextField("如 3:4", text: $brief.aspectRatio)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 110)
                    }
                    GridRow {
                        Label2("禁止出现")
                        TextField("逗号分隔", text: list(\.mustAvoid))
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Label2("必须保留")
                        TextField("逗号分隔", text: list(\.mustKeep))
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
        }
    }

    private func optional(_ keyPath: WritableKeyPath<Brief, String?>) -> Binding<String> {
        Binding(
            get: { brief[keyPath: keyPath] ?? "" },
            set: { brief[keyPath: keyPath] = $0.isEmpty ? nil : $0 })
    }

    private func list(_ keyPath: WritableKeyPath<Brief, [String]?>) -> Binding<String> {
        Binding(
            get: { (brief[keyPath: keyPath] ?? []).joined(separator: "，") },
            set: { text in
                let items = text
                    .split(whereSeparator: { "，,、;；".contains($0) })
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                brief[keyPath: keyPath] = items.isEmpty ? nil : items
            })
    }
}

private struct Label2: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .frame(width: 62, alignment: .leading)
    }
}

// MARK: - 提示词

private struct PromptCard: View {
    let model: ModelId
    let result: Result<CompiledPrompt, CompileError>
    var canGenerate: Bool = false
    var isGenerating: Bool = false
    var isBusy: Bool = false
    var onGenerate: ((String) -> Void)?

    var body: some View {
        SectionCard(title: model.displayName, subtitle: nil) {
            switch result {
            case .failure(let error):
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("编译被拦下（\(error.rule)）")
                            .font(.system(size: 12, weight: .medium))
                        Text(error.message)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

            case .success(let prompt):
                if let text = prompt.text2img, !text.isEmpty {
                    PromptBlock(label: "文生图", text: text)

                    if canGenerate {
                        HStack(spacing: 8) {
                            Button {
                                onGenerate?(text)
                            } label: {
                                if isGenerating {
                                    HStack(spacing: 6) {
                                        ProgressView().controlSize(.small)
                                        Text("生成中…")
                                    }
                                } else {
                                    Label("生成图片", systemImage: "wand.and.stars")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(isBusy)

                            Text(isGenerating ? "单张约 3~4 分钟，别关窗口" : "用上面这段提示词原样生成，不做任何加工")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.top, 2)
                    }
                }
                if let edit = prompt.img2imgEdit, !edit.isEmpty {
                    PromptBlock(label: "垫图局部编辑", text: edit)
                }
                if let ref = prompt.img2imgStyleRef, !ref.isEmpty {
                    PromptBlock(label: "垫图风格参考", text: ref)
                }
                if let proto = prompt.refProtocol, !proto.isEmpty {
                    PromptBlock(label: "参考槽协议", text: proto)
                }
                if !prompt.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(prompt.notes, id: \.self) { note in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                                Text(note)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }
}

private struct PromptBlock: View {
    let label: String
    let text: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copied = true
                    Task {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        copied = false
                    }
                } label: {
                    Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10))
                }
                .buttonStyle(.borderless)
            }
            Text(text)
                .font(.system(size: 12))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
        }
    }
}

// MARK: - 生成结果

/// 生成历史。
///
/// 这张卡最重要的不是图，是**「提示词逐字一致」那个徽标**——生图 agent 中间会不会
/// 改写提示词，决定了这张图能不能用来评判编译器。改写过的图只能看个热闹，
/// 不能当证据，所以这一条必须显示在图旁边，而不是藏在详情里。
private struct GenerationsCard: View {
    let history: [(record: GenerationStore.Record, imageURL: URL)]
    /// 正在跑的那次是什么时候开始的。nil = 没在跑。
    let startedAt: Date?
    let error: String?
    let providerName: String?
    let onDelete: (String) -> Void

    var body: some View {
        if providerName == nil {
            SectionCard(title: "生成", subtitle: nil) {
                Text("本机没找到 codex，生图不可用。提示词照常可以复制出去用。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        } else if startedAt != nil || error != nil || !history.isEmpty {
            SectionCard(
                title: "生成结果",
                subtitle: history.isEmpty ? providerName : "\(history.count) 张 · \(providerName ?? "")"
            ) {
                if let error {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let startedAt {
                    TaskProgress(
                        startedAt: startedAt,
                        expected: Pace.generation,
                        tint: .purple,
                        label: history.isEmpty ? "生成中 · 第一张要等 3~4 分钟" : "生成中",
                        icon: "wand.and.stars",
                        compact: false
                    )
                    .padding(.bottom, 2)
                }

                ForEach(history, id: \.record.jobID) { entry in
                    GenerationRow(
                        record: entry.record,
                        imageURL: entry.imageURL,
                        onDelete: { onDelete(entry.record.jobID) }
                    )
                }
            }
        }
    }
}

private struct GenerationRow: View {
    let record: GenerationStore.Record
    let imageURL: URL
    let onDelete: () -> Void

    @State private var image: NSImage?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if let image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                } else {
                    Rectangle().fill(.quaternary)
                }
            }
            .frame(width: 132, height: 132)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .task(id: imageURL) {
                image = await ThumbnailCache.shared.thumbnail(for: imageURL, maxPixel: 400)
            }

            VStack(alignment: .leading, spacing: 6) {
                // 实验有效性判据放最上面
                if record.promptIsVerbatim {
                    Badge(
                        text: "提示词逐字一致", systemImage: "checkmark.seal.fill", tint: .green)
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        Badge(
                            text: "提示词被改写", systemImage: "exclamationmark.triangle.fill",
                            tint: .orange)
                        Text("这张图不能用来评判编译器——分不清偏差来自编译器还是中间改写。")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !record.usedBuiltinTool {
                    Badge(
                        text: "生图路径 \(record.toolUsed ?? "未知")",
                        systemImage: "questionmark.circle", tint: .orange)
                }

                // 画幅在内置模式下是软约束，中没中必须一眼看见——
                // 没中的图拿去量构图数据就是错的。
                if record.aspectMatches == false, let want = record.requestedAspect {
                    Badge(
                        text: "画幅没中（要 \(want)）", systemImage: "aspectratio", tint: .orange)
                }

                HStack(spacing: 10) {
                    Text(record.pixelSize)
                        .font(.system(size: 11, design: .monospaced))
                    Text(record.model.displayName)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Text(record.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                Spacer(minLength: 0)

                HStack(spacing: 10) {
                    Button("在访达中显示") {
                        NSWorkspace.shared.activateFileViewerSelecting([imageURL])
                    }
                    .font(.system(size: 10))
                    .buttonStyle(.borderless)

                    Button("删除", role: .destructive, action: onDelete)
                        .font(.system(size: 10))
                        .buttonStyle(.borderless)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct Badge: View {
    let text: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage).font(.system(size: 9))
            Text(text).font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(tint.opacity(0.14), in: Capsule())
    }
}

// MARK: - 卡片外壳

struct SectionCard<Content: View>: View {
    let title: String?
    var subtitle: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if title != nil || subtitle != nil {
                VStack(alignment: .leading, spacing: 2) {
                    if let title {
                        Text(title).font(.system(size: 13, weight: .semibold))
                    }
                    if let subtitle {
                        Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
    }
}
