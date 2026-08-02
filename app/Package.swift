// swift-tools-version: 5.9
import PackageDescription

// 两个 target 是刻意的：
//   FormlessCore —— 库，装 StyleSpec / Compile / Lint / Drift，可被 XCTest 直接测。
//   Formless     —— 可执行，只装 @main 和 UI。
// 逻辑不能放进可执行 target：带 @main 的 target 做 @testable import 会撞链接问题，
// 而 A1/A2 要往 Core 里移植约 1272 行逻辑和 43 个测试用例，可测性是硬要求。
let package = Package(
    name: "Formless",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "FormlessCore",
            path: "Sources/FormlessCore",
            // Resources/ 里有：MockVisionProvider 的假数据（从 core-ts/evals/fixtures/
            // 镜像，有测试盯着字节一致）、分析指令模板、随包分发的 StyleSpec schema。
            resources: [.process("Resources")],
            // 系统自带 SQLite，不引第三方依赖
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "Formless",
            dependencies: ["FormlessCore"],
            path: "Sources/Formless",
            // Resources/Sounds 里是完成提示音。放在可执行 target 而不是 Core：
            // 发声是界面反馈，Core 必须保持无 AppKit、能在没有窗口的情况下跑测试。
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "FormlessCoreTests",
            dependencies: ["FormlessCore"],
            path: "Tests/FormlessCoreTests"
        ),
    ]
)
