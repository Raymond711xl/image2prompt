import Testing

@testable import FormlessCore

// 用 swift-testing 而不是 XCTest：XCTest.framework 随 Xcode 走，
// 只装 Command Line Tools 的机器上 `import XCTest` 直接失败。
// swift-testing 随 Swift 工具链走，无 Xcode 也能跑——这决定了 A1/A2 那 43 个
// 移植用例能不能在装 Xcode 之前就跑起来。

@Test("StyleSpec 版本号与仓库根 schema 对得上")
func styleSpecVersionMatchesSchema() {
    #expect(BuildInfo.styleSpecVersion == "0.1")
}

@Test("当前里程碑标记正确")
func milestoneIsA0() {
    #expect(BuildInfo.milestone == "A0")
}
