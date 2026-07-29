import Foundation
import Testing

@testable import FormlessCore

// bundle id 是数据目录名和 Keychain service 名。打包脚本里写死了一份，Swift 里写死了一份，
// 两份对不上的后果不是编译错误而是**数据静默消失**：装上新版打开，库是空的。
// 所以这里真的去读那个 shell 脚本。

private let bundleScript = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // → Tests/FormlessCoreTests
    .deletingLastPathComponent()  // → Tests
    .deletingLastPathComponent()  // → app
    .appendingPathComponent("Scripts/bundle.sh")

@Test("打包脚本里的三个名字和 AppIdentity 一致")
func bundleScriptMatchesIdentity() throws {
    let script = try String(contentsOf: bundleScript, encoding: .utf8)

    #expect(script.contains("APP_NAME=\"\(AppIdentity.displayName)\""))
    #expect(script.contains("EXECUTABLE=\"\(AppIdentity.codeName)\""))
    #expect(script.contains("BUNDLE_ID=\"\(AppIdentity.bundleID)\""))
}

@Test("旧 bundle id 与新的不同，迁移逻辑才有意义")
func legacyIDDiffers() {
    #expect(AppIdentity.legacyBundleID != AppIdentity.bundleID)
}
