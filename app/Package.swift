// swift-tools-version: 5.9
import PackageDescription

// 两个 target 是刻意的：
//   Image2PromptCore —— 库，装 StyleSpec / Compile / Lint / Drift，可被 XCTest 直接测。
//   Image2Prompt     —— 可执行，只装 @main 和 UI。
// 逻辑不能放进可执行 target：带 @main 的 target 做 @testable import 会撞链接问题，
// 而 A1/A2 要往 Core 里移植约 1272 行逻辑和 43 个测试用例，可测性是硬要求。
let package = Package(
    name: "Image2Prompt",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "Image2PromptCore",
            path: "Sources/Image2PromptCore",
            // Resources/ 里的 StyleSpec 是从 core-ts/evals/fixtures/ 镜像过来的，
            // 给 MockVisionProvider 当假数据。有一条测试盯着两边字节一致，防漂移。
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "Image2Prompt",
            dependencies: ["Image2PromptCore"],
            path: "Sources/Image2Prompt"
        ),
        .testTarget(
            name: "Image2PromptCoreTests",
            dependencies: ["Image2PromptCore"],
            path: "Tests/Image2PromptCoreTests"
        ),
    ]
)
