import Foundation
import Testing

@testable import Image2PromptCore

// 跨实现一致性测试。
//
// 同一套规则有 TS 和 Swift 两份实现，漂移是必然风险。这组测试是两边的**契约**：
// golden 文件由 core-ts 的编译器产出，Swift 版必须逐字复现。
//
// 任何一侧改了措辞而另一侧没跟上，这里立刻炸。规则先在 core-ts 改、跑通 Track B
// 验证，再移植进 Swift——这条流水线靠这些测试守住。

private let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

private let fixtures = repoRoot.appendingPathComponent("core-ts/evals/fixtures")
private let golden = repoRoot.appendingPathComponent("core-ts/evals/golden")

private struct GoldenPrompt: Decodable {
    let model: String
    let aspect_ratio: String
    let text2img: String?
    let img2img_edit: String?
    let img2img_style_ref: String?
    let ref_protocol: String?
    let notes: [String]
}

private struct GoldenFile: Decodable {
    let style_dna: String
    let prompts: [GoldenPrompt]
}

private func runCase(spec specName: String, brief briefName: String) throws {
    let spec = try StyleSpec.decode(
        contentsOf: fixtures.appendingPathComponent("\(specName).stylespec.json"))
    let brief = try Brief.decode(
        contentsOf: fixtures.appendingPathComponent("\(briefName).brief.json"))
    let expected = try JSONDecoder().decode(
        GoldenFile.self,
        from: Data(contentsOf: golden.appendingPathComponent("\(specName)--\(briefName).json")))

    #expect(spec.styleDna == expected.style_dna)

    for want in expected.prompts {
        guard let model = ModelId(rawValue: want.model) else {
            Issue.record("golden 里有未知模型 \(want.model)")
            continue
        }
        let got = try Compiler.compile(spec, brief, model: model)

        #expect(got.aspectRatio == want.aspect_ratio, "[\(want.model)] aspect_ratio 不一致")
        #expect(got.text2img == want.text2img, "[\(want.model)] text2img 与 core-ts 不一致")
        #expect(got.img2imgEdit == want.img2img_edit, "[\(want.model)] img2img_edit 与 core-ts 不一致")
        #expect(
            got.img2imgStyleRef == want.img2img_style_ref,
            "[\(want.model)] img2img_style_ref 与 core-ts 不一致")
        #expect(got.refProtocol == want.ref_protocol, "[\(want.model)] ref_protocol 与 core-ts 不一致")
        #expect(got.notes == want.notes, "[\(want.model)] notes 与 core-ts 不一致")
    }
}

@Test("编译一致性：红色像素风海报 → 微信头图")
func parityRedPixelWechat() throws {
    try runCase(spec: "red-pixel-newyear-poster", brief: "glucose-meter-wechat-cover")
}

@Test("编译一致性：红色像素风海报 → 垫图局部编辑（边界四纪律）")
func parityRedPixelEdit() throws {
    // 这条最关键：边界控制四纪律的完整产出，一个字都不能差
    try runCase(spec: "red-pixel-newyear-poster", brief: "pixel-swap-edit")
}

@Test("编译一致性：白色高调产品图 → 微信头图")
func parityWhiteHighKey() throws {
    try runCase(spec: "white-highkey-scale-hero", brief: "glucose-meter-wechat-cover")
}

// MARK: - 边界四纪律的拦截行为

private func loadSpec() throws -> StyleSpec {
    try StyleSpec.decode(
        contentsOf: fixtures.appendingPathComponent("red-pixel-newyear-poster.stylespec.json"))
}

private func briefWithEdit(_ edit: EditIntent) -> Brief {
    Brief(purpose: "poster", aspectRatio: "3:4", subject: "血糖仪", edit: edit)
}

@Test("纪律一：scope_anchor 为空则编译失败")
func rejectsEmptyScope() throws {
    let brief = briefWithEdit(
        EditIntent(
            scopeAnchor: "",
            protect: [.init(element: "顶部大字", originalContent: "NEW YEAR")],
            replace: [.init(target: "中央图形", newContent: "血糖仪")]))
    #expect(throws: CompileError.self) {
        _ = try Compiler.compile(try loadSpec(), brief, model: .gptImage)
    }
}

@Test("纪律一：scope_anchor 用产权概念词则编译失败")
func rejectsOwnershipAnchor() throws {
    let brief = briefWithEdit(
        EditIntent(
            scopeAnchor: "我们的展位区域",
            protect: [.init(element: "顶部大字", originalContent: "NEW YEAR")],
            replace: [.init(target: "中央图形", newContent: "血糖仪")]))
    #expect(throws: CompileError.self) {
        _ = try Compiler.compile(try loadSpec(), brief, model: .gptImage)
    }
}

@Test("纪律二：保护项没写原有内容则编译失败")
func rejectsProtectWithoutOriginal() throws {
    let brief = briefWithEdit(
        EditIntent(
            scopeAnchor: "画面中央的方形图形",
            protect: [.init(element: "顶部大字", originalContent: "")],
            replace: [.init(target: "中央图形", newContent: "血糖仪")]))
    #expect(throws: CompileError.self) {
        _ = try Compiler.compile(try loadSpec(), brief, model: .gptImage)
    }
}

@Test("纪律三：替换目标含扫射量词则编译失败")
func rejectsBlanketQuantifier() throws {
    for bad in ["所有图形", "全部文字", "每个色块", "一切装饰"] {
        let brief = briefWithEdit(
            EditIntent(
                scopeAnchor: "画面中央的方形图形",
                protect: [.init(element: "顶部大字", originalContent: "NEW YEAR")],
                replace: [.init(target: bad, newContent: "血糖仪")]))
        #expect(throws: CompileError.self, "「\(bad)」含扫射量词，应被拦下") {
            _ = try Compiler.compile(try loadSpec(), brief, model: .gptImage)
        }
    }
}

@Test("编辑指令不齐只拦 GPT Image，不影响即梦文生图")
func editFailureDoesNotBreakJimeng() throws {
    let brief = briefWithEdit(EditIntent(scopeAnchor: ""))
    let results = Compiler.compileAll(try loadSpec(), brief)

    let jimeng = results.first { $0.model == .jimeng }
    let gpt = results.first { $0.model == .gptImage }

    if case .success(let prompt) = jimeng?.result {
        #expect(prompt.text2img?.isEmpty == false)
    } else {
        Issue.record("即梦不该因为 GPT Image 的编辑块不齐而失败")
    }
    if case .success = gpt?.result {
        Issue.record("GPT Image 应该因为 scope_anchor 为空而失败")
    }
}
