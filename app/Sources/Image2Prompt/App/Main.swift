import AppKit
import Image2PromptCore
import SwiftUI

// 不用 SwiftUI 的 App/Scene 生命周期，改由 AppKit 驱动。
// 原因：菜单栏图标要能接收拖放，必须自己持有 NSStatusItem；
// SwiftUI 的 MenuBarExtra 把它藏起来了，注册不了拖放类型。
@main
enum Main {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // .accessory：只在菜单栏，不占 Dock，不抢主菜单栏
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController!
    private var mainWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private let state = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = StatusItemController()

        statusItem.onDrop = { [weak self] urls in
            guard let self else { return }
            self.state.queue.enqueue(urls)
            self.showMainWindow()
        }

        statusItem.onClick = { [weak self] in
            self?.showMainWindow()
        }

        state.onSettingsRequested = { [weak self] in self?.showSettingsWindow() }
        state.onQuitRequested = { NSApplication.shared.terminate(nil) }

        // 队列忙的时候图标变一下，不打开窗口也知道还在跑
        state.onBusyChanged = { [weak self] busy in self?.statusItem.setBusy(busy) }
    }

    // MARK: - 窗口

    private func showMainWindow() {
        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = makeWindow(
            title: "Image to Prompt",
            size: NSSize(width: 980, height: 640),
            root: MainView().environment(state)
        )
        window.delegate = self
        mainWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showSettingsWindow() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = makeWindow(
            title: "设置",
            size: NSSize(width: 520, height: 420),
            root: SettingsView().environment(state)
        )
        window.delegate = self
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow(title: String, size: NSSize, root: some View) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.titlebarAppearsTransparent = false
        window.isReleasedWhenClosed = false
        window.center()
        window.contentViewController = NSHostingController(rootView: root)
        return window
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow else { return }
        // 置空，下次点击重新创建。菜单栏工具关窗不等于退出。
        if closing === mainWindow { mainWindow = nil }
        if closing === settingsWindow { settingsWindow = nil }
    }
}
