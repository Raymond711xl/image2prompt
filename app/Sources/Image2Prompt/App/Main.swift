import AppKit
import Image2PromptCore
import SwiftUI
import UniformTypeIdentifiers

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
        installMainMenu()

        statusItem = StatusItemController()

        statusItem.onDrop = { [weak self] urls in
            guard let self else { return }
            self.state.queue.enqueue(urls)
            self.showMainWindow()
        }
        statusItem.onOpenWindow = { [weak self] in self?.showMainWindow() }
        statusItem.onOpenSettings = { [weak self] in self?.showSettingsWindow() }
        statusItem.onImportFolder = { [weak self] in self?.importFolder() }
        statusItem.onTogglePause = { [weak self] in
            guard let queue = self?.state.queue else { return }
            queue.isPaused ? queue.resume() : queue.pause()
        }
        statusItem.queueSnapshot = { [weak self] in
            guard let queue = self?.state.queue else {
                return .init(total: 0, done: 0, active: 0, pending: 0, isPaused: false)
            }
            return .init(
                total: queue.items.count, done: queue.doneCount,
                active: queue.activeCount, pending: queue.pendingCount,
                isPaused: queue.isPaused)
        }

        state.onSettingsRequested = { [weak self] in self?.showSettingsWindow() }
        state.onImportFolderRequested = { [weak self] in self?.importFolder() }
        state.onQuitRequested = { NSApplication.shared.terminate(nil) }
        // 队列忙的时候图标变一下，不打开窗口也知道还在跑
        state.onBusyChanged = { [weak self] busy in self?.statusItem.setBusy(busy) }
    }

    // MARK: - 主菜单
    //
    // LSUIElement 应用不显示菜单栏，但设置了 mainMenu 之后键盘快捷键仍然生效。
    // 不装它，窗口聚焦时 ⌘Q 关不掉程序、⌘W 关不掉窗口——只能去菜单栏点。
    private func installMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "设置…", action: #selector(menuOpenSettings), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "隐藏 Image to Prompt", action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "退出 Image to Prompt", action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        appMenu.items.forEach { if $0.action == #selector(menuOpenSettings) { $0.target = self } }
        appItem.submenu = appMenu
        main.addItem(appItem)

        // 编辑菜单：没有它，输入框里 ⌘C/⌘V/⌘A 全部失效
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(
            withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(
            withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(
            withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(
            withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(
            withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(
            withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        NSApp.mainMenu = main
    }

    @objc private func menuOpenSettings() { showSettingsWindow() }

    // MARK: - 导入文件夹

    /// 一张张拖不现实——30 张验证集、几百张图库都得靠这个。
    /// 只扫一层，不递归：递归很容易把整个下载目录卷进来。
    private func importFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "导入"
        panel.message = "选择包含参考图的文件夹（只扫描该层，不进子文件夹）"

        guard panel.runModal() == .OK else { return }

        let images = panel.urls.flatMap { folder -> [URL] in
            let contents =
                (try? FileManager.default.contentsOfDirectory(
                    at: folder, includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])) ?? []
            return contents.filter { url in
                guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
                return type.conforms(to: .image)
            }
        }

        guard !images.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "没找到图片"
            alert.informativeText = "所选文件夹里没有可识别的图片文件。"
            alert.runModal()
            return
        }

        state.queue.enqueue(images.sorted { $0.lastPathComponent < $1.lastPathComponent })
        showMainWindow()
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
            size: Self.preferredMainSize(),
            root: MainView().environment(state)
        )
        // 侧栏 + 详情页两栏，太窄会把大图压成一条。低于这个尺寸没有可用性可言。
        window.minSize = NSSize(width: 900, height: 620)
        // 记住你调过的尺寸和位置，下次按你的来，不再回到默认值
        window.setFrameAutosaveName("MainWindow")
        window.delegate = self
        mainWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 默认尺寸按屏幕比例给，不写死像素。
    /// 写死 980×640 在你的屏幕上就是「太小看不清」——这个窗口的主要内容是一张参考图，
    /// 图小了整个工具就没意义了。
    private static func preferredMainSize() -> NSSize {
        guard let visible = NSScreen.main?.visibleFrame else {
            return NSSize(width: 1280, height: 860)
        }
        return NSSize(
            width: min(max(visible.width * 0.78, 1100), 1760),
            height: min(max(visible.height * 0.82, 760), 1200)
        )
    }

    private func showSettingsWindow() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = makeWindow(
            title: "设置",
            size: NSSize(width: 560, height: 620),
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
