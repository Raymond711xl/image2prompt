import AppKit
import FormlessCore
import SwiftUI

struct DetailView: View {
    let item: QueueItem
    let spec: StyleSpec
    var onBriefChanged: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Preview(url: item.imageURL)
                ContentTextCard(spec: spec)
                StyleDNACard(spec: spec)
                PaletteCard(palette: spec.palette, color: spec.color)
                FieldsCard(spec: spec)
                LeakageCard(spec: spec)
                BriefSection(item: item, spec: spec, onBriefChanged: onBriefChanged)
            }
            .padding(20)
            .frame(maxWidth: 960, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(item.fileName)
    }
}

// MARK: - 大图

private struct Preview: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Rectangle().fill(.quaternary)
            }
        }
        // 参考图是判断依据，不是配图。给足高度，随窗口一起长。
        .frame(minHeight: 260, maxHeight: 560)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .task(id: url) {
            // 2400px 覆盖 Retina 下最宽 1200pt 的显示区。参考图的材质和颗粒是判断依据，
            // 预览糊了就等于看不清风格。
            image = await ThumbnailCache.shared.thumbnail(for: url, maxPixel: 2400)
        }
    }
}

// MARK: - 内容与文字

/// v0.2 新增：content 是隔离区（换主体时整个丢弃），但载体判断和逐段文字排版
/// 是判断这张图能不能被信任复现的第一道证据，所以摆在风格 DNA 前面。
private struct ContentTextCard: View {
    let spec: StyleSpec

    private static let carrierLabels: [CarrierTypeValue: String] = [
        .flatDesign: "平面设计原图本身",
        .printOnObject: "印在物体上的照片",
        .screenshot: "界面 / 作品页截图",
        .photoScene: "实景照片",
        .unknown: "无法判断",
    ]

    var body: some View {
        let carrier = spec.content.carrierType
        Card(title: "内容与文字", subtitle: "画面里有什么、文字怎么排——换主体时这块会被丢弃") {
            VStack(alignment: .leading, spacing: 4) {
                Text(spec.content.subject)
                    .font(.system(size: 12))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Text(spec.content.scene)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 6) {
                Tag(
                    text: "载体 \(Self.carrierLabels[carrier.value] ?? carrier.value.rawValue)",
                    tint: carrier.confidence < 0.6 ? .orange : .secondary
                )
                Tag(text: "置信度 \(Int(carrier.confidence * 100))%", tint: .secondary)
                if spec.composition.panelCount > 1 {
                    Tag(text: "\(spec.composition.panelCount) 个版块", tint: .accentColor)
                }
            }
            .padding(.top, 6)

            if let candidates = carrier.candidates, !candidates.isEmpty {
                Text("备选载体：\(candidates.joined(separator: "、"))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.top, 3)
            }

            if let panels = spec.composition.panels, !panels.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(panels.enumerated()), id: \.offset) { i, p in
                        Text("第 \(i + 1) 块（\(p.region)）：\(p.role)")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 3)
            }

            if !spec.content.onImageText.isEmpty {
                Divider().padding(.vertical, 6)
                Text("文字 \(spec.content.onImageText.count) 段")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(Array(spec.content.onImageText.enumerated()), id: \.offset) { _, t in
                        TextElementRow(item: t)
                    }
                }
                .padding(.top, 4)
            }
        }
    }
}

private struct TextElementRow: View {
    let item: OnImageText

    private var ocrTint: Color {
        switch item.ocrStatus {
        case .exact: return .secondary
        case .approx: return .yellow
        case .unclear: return .orange
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if let hex = item.color, hex.hasPrefix("#") {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(hex: hex))
                    .frame(width: 12, height: 12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3).strokeBorder(.separator, lineWidth: 0.5)
                    )
                    .padding(.top, 2)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.ocrStatus == .unclear ? "〈\(item.text)〉" : "\u{201C}\(item.text)\u{201D}")
                    .font(.system(size: 12))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                if let breaks = item.lineBreaks, breaks.count > 1 {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(breaks, id: \.self) { line in
                            Text("↵ \(line)")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                HStack(spacing: 5) {
                    Tag(text: item.position, tint: .secondary)
                    Tag(text: item.ocrStatus.rawValue, tint: ocrTint)
                    if let layer = item.layer { Tag(text: layer.rawValue, tint: .secondary) }
                    if let size = item.relativeSize { Tag(text: size.rawValue, tint: .secondary) }
                    if let d = item.distortion, d != .none { Tag(text: d.rawValue, tint: .accentColor) }
                }

                if let note = item.typefaceNote, !note.isEmpty {
                    Text(note).font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - 风格 DNA

private struct StyleDNACard: View {
    let spec: StyleSpec

    var body: some View {
        Card(
            title: "风格 DNA",
            subtitle: "与画面内容无关，可套用任何主体",
            copyable: spec.styleDna
        ) {
            Text(spec.styleDna)
                .font(.system(size: 13))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if let en = spec.styleDnaEn, !en.isEmpty {
                Divider().padding(.vertical, 4)
                Text(en)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 6) {
                ForEach(spec.styleFamily, id: \.name) { family in
                    Tag(
                        text: family.name,
                        tint: family.role == .borrowed ? .secondary : .accentColor
                    )
                }
            }
            .padding(.top, 6)
        }
    }
}

// MARK: - 色板

private struct PaletteCard: View {
    let palette: [PaletteEntry]
    let color: ColorInfo

    var body: some View {
        Card(title: "色板", subtitle: "hex + 占比，色彩偏移在这上面做运算") {
            // 按占比拉成一条比例条，一眼看出主色关系
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(palette, id: \.hex) { entry in
                        Color(hex: entry.hex)
                            .frame(width: max(2, geo.size.width * entry.ratio))
                    }
                    // 未列出的杂色。palette 只列主色，合计不必等于 1。
                    let listed = palette.reduce(0) { $0 + $1.ratio }
                    if listed < 0.999 {
                        Rectangle()
                            .fill(.quaternary)
                            .frame(width: geo.size.width * (1 - listed))
                    }
                }
            }
            .frame(height: 26)
            .clipShape(RoundedRectangle(cornerRadius: 5))

            VStack(alignment: .leading, spacing: 5) {
                ForEach(palette, id: \.hex) { entry in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(hex: entry.hex))
                            .frame(width: 14, height: 14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 3).strokeBorder(
                                    .separator, lineWidth: 0.5))
                        Text(entry.hex).font(.system(size: 11, design: .monospaced))
                        Text(entry.role.rawValue)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        if let name = entry.nameCn {
                            Text(name).font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(Int(entry.ratio * 100))%")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 8)

            HStack(spacing: 6) {
                Tag(text: "饱和 \(color.saturation.rawValue)", tint: .secondary)
                Tag(text: "色温 \(color.temperature.rawValue)", tint: .secondary)
                Tag(text: "对比 \(color.contrast.rawValue)", tint: .secondary)
                if let key = color.brightnessKey {
                    Tag(text: key.rawValue, tint: .secondary)
                }
            }
            .padding(.top, 8)
        }
    }
}

// MARK: - 关键字段

private struct FieldsCard: View {
    let spec: StyleSpec

    private var rows: [(String, String)] {
        let c = spec.composition
        let s = spec.source
        var out: [(String, String)] = [
            ("媒介", spec.mediumDetail ?? spec.medium.rawValue),
            ("广告类型", spec.adType.rawValue),
            (
                "画幅",
                "\(c.aspectRatio)（精确 \(s.width)×\(s.height)，\(String(format: "%.2f", s.aspectExact))）"
            ),
            ("景别 / 视角", "\(c.shot.rawValue) · \(c.angle.rawValue)"),
            ("主体位置", "\(c.subjectPosition)，占比 \(Int(c.subjectCoverage * 100))%"),
            ("负空间", "\(c.negativeSpace.region)，\(Int(c.negativeSpace.ratio * 100))%"),
            ("密度", c.density.rawValue),
            ("形态", "\(spec.formLanguage.geometry.rawValue) · \(spec.formLanguage.edge.rawValue)"),
            (
                "光线",
                "\(spec.lighting.direction.rawValue) · \(spec.lighting.quality.rawValue) · 对比 \(spec.lighting.contrast.rawValue)"
            ),
        ]
        if let stacking = c.elementStacking, !stacking.isEmpty {
            out.append(("前后关系", stacking.joined(separator: " → ")))
        }
        if let align = spec.typography.implicitAlignment, !align.isEmpty {
            out.append(("文字隐形关系", align))
        }
        out.append(("气质", spec.mood.joined(separator: "、")))
        return out
    }

    var body: some View {
        Card(title: "视觉语法", subtitle: "调参盘会在这些字段上做受控偏移") {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(rows, id: \.0) { label, value in
                    HStack(alignment: .top, spacing: 12) {
                        Text(label)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(width: 76, alignment: .leading)
                        Text(value)
                            .font(.system(size: 12))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if spec.confidence.uncertainFields.isEmpty == false {
                Divider().padding(.vertical, 6)
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "questionmark.circle")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("看不准的维度")
                            .font(.system(size: 11, weight: .medium))
                        Text(spec.confidence.uncertainFields.joined(separator: "、"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - 内容泄漏

private struct LeakageCard: View {
    let spec: StyleSpec

    var body: some View {
        if let leaks = spec.contentLeakage, !leaks.isEmpty {
            Card(title: "内容泄漏", subtitle: "风格块里混进了这张图的具体内容，换主体时会跟着跑出来") {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(leaks, id: \.phrase) { leak in
                        HStack(spacing: 8) {
                            Image(
                                systemName: leak.severity == .high
                                    ? "exclamationmark.octagon.fill" : "exclamationmark.triangle"
                            )
                            .foregroundStyle(leak.severity == .high ? .red : .orange)
                            Text("「\(leak.phrase)」")
                                .font(.system(size: 12))
                            Text("于 \(leak.field)")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 复用组件

private struct Card<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    var copyable: String? = nil
    @ViewBuilder let content: Content

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    if let subtitle {
                        Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let copyable {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(copyable, forType: .string)
                        copied = true
                        Task {
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            copied = false
                        }
                    } label: {
                        Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                }
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct Tag: View {
    let text: String
    var tint: Color = .accentColor

    var body: some View {
        Text(text)
            .font(.system(size: 10))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.14), in: Capsule())
            .foregroundStyle(tint)
    }
}

extension Color {
    /// #RRGGBB → Color。schema 用正则保证了格式，这里不做容错。
    init(hex: String) {
        let clean = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let value = UInt32(clean, radix: 16) ?? 0
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
