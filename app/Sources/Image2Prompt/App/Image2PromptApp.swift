import AppKit
import Image2PromptCore
import SwiftUI

/// A0 的全部内容：一个能启动、能显示、能退出的空壳菜单栏 App。
///
/// 这里刻意什么都不做。A0 唯一要证明的是构建链路通了——
/// 没有 Xcode，只用 Command Line Tools + SwiftPM，能编出可运行的 macOS 菜单栏程序。
/// 拖放接收、待办队列、Anthropic 调用、结果页都是 A1 的事。
@main
struct Image2PromptApp: App {
    var body: some Scene {
        MenuBarExtra("Image to Prompt", systemImage: "wand.and.stars") {
            Text("Image to Prompt")
            Text("里程碑 \(BuildInfo.milestone) · StyleSpec v\(BuildInfo.styleSpecVersion)")

            Divider()

            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
