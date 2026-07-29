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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            InputCard(
                item: item, spec: spec, onParsed: compile,
                onChanged: { onBriefChanged?() })

            if let brief = item.brief {
                ParsedCard(
                    brief: Binding(
                        get: { brief },
                        set: {
                            item.brief = $0
                            compile()
                            onBriefChanged?()
                        }
                    ))

                ForEach(compiled, id: \.model) { entry in
                    PromptCard(model: entry.model, result: entry.result)
                }
            }
        }
        .onAppear { if item.brief != nil { compile() } }
        .onChange(of: item.id) { _, _ in compiled = [] }
    }

    private func compile() {
        guard let brief = item.brief else {
            compiled = []
            return
        }
        compiled = Compiler.compileAll(spec, brief)
    }
}

// MARK: - 自由文本输入

private struct InputCard: View {
    @Bindable var item: QueueItem
    let spec: StyleSpec
    let onParsed: () -> Void
    let onChanged: () -> Void

    var body: some View {
        SectionCard(title: "这次要生成什么", subtitle: "随便写，写完点解析——写得越具体，解析越准") {
            TextEditor(text: $item.briefText)
                .font(.system(size: 12))
                .frame(minHeight: 88)
                .padding(6)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
                .overlay(alignment: .topLeading) {
                    if item.briefText.isEmpty {
                        Text(
                            "例：用这个风格做一张微信公众号头图，主体换成一台血糖仪，\n标题「新年焕新」，不要人物，保留原来的红色"
                        )
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                    }
                }

            HStack {
                Button("解析") {
                    item.brief = HeuristicBriefParser.parseSync(text: item.briefText, spec: spec)
                    onParsed()
                    onChanged()
                }
                .buttonStyle(.borderedProminent)
                .disabled(item.briefText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if item.brief != nil {
                    Button("清空") {
                        item.brief = nil
                        onParsed()
                        onChanged()
                    }
                    .buttonStyle(.borderless)
                }

                Spacer()

                Text("离线粗解析，解析完请核对下面的字段")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - 可编辑的解析结果

private struct ParsedCard: View {
    @Binding var brief: Brief

    var body: some View {
        SectionCard(title: "解析结果", subtitle: "解析会漏会错，这里改了立刻重新编译") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Label2("主体")
                    TextField("这次要画什么", text: $brief.subject)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Label2("细节")
                    TextField(
                        "外观、材质、颜色（可空）",
                        text: Binding(
                            get: { brief.subjectDetail ?? "" },
                            set: { brief.subjectDetail = $0.isEmpty ? nil : $0 })
                    )
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
                    Label2("标题文案")
                    TextField(
                        "画面上的标题（可空）",
                        text: Binding(
                            get: { brief.copy?.title ?? "" },
                            set: {
                                var c = brief.copy ?? CopyBlock()
                                c.title = $0.isEmpty ? nil : $0
                                brief.copy = c.isEmpty ? nil : c
                            })
                    )
                    .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Label2("禁止出现")
                    TextField(
                        "逗号分隔",
                        text: Binding(
                            get: { (brief.mustAvoid ?? []).joined(separator: "，") },
                            set: { brief.mustAvoid = splitList($0) })
                    )
                    .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Label2("必须保留")
                    TextField(
                        "逗号分隔",
                        text: Binding(
                            get: { (brief.mustKeep ?? []).joined(separator: "，") },
                            set: { brief.mustKeep = splitList($0) })
                    )
                    .textFieldStyle(.roundedBorder)
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

            Text("关闭时先生成主视觉，标题后期以可编辑图层叠加——文字正确性和排版更可控。")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    private func splitList(_ text: String) -> [String]? {
        let items =
            text
            .split(whereSeparator: { "，,、;；".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return items.isEmpty ? nil : items
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

// MARK: - 卡片外壳

struct SectionCard<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                if let subtitle {
                    Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
    }
}
