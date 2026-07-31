import AppKit
import UniformTypeIdentifiers

/// 菜单栏图标本身就是投放目标：拖图上去直接接收。
///
/// 这是 A1 的核心交互，也是整个 App 存在的理由——比"打开窗口再拖进去"少两步。
/// 必须走 AppKit：SwiftUI 的 MenuBarExtra 不暴露底层 NSStatusItem，注册不了拖放类型。
///
/// 图标同时挂一个菜单：菜单栏应用没有 Dock 图标、也不显示主菜单栏，
/// **这个菜单是用户唯一能找到设置和退出的地方**。没有它就只能杀进程。
///
/// 更进一步的"拖动时自动弹出接收框"（Yoink 那种）需要全局监听拖拽会话开始，
/// 留到后续里程碑。现在是标准做法：图标常驻，拖上去即接收。
@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let dropView: StatusDropView
    private let menu = NSMenu()

    var onDrop: (([URL]) -> Void)?
    var onOpenWindow: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onTogglePause: (() -> Void)?
    var onImportFolder: (() -> Void)?
    /// 菜单展开时读一次队列状态，用来渲染实时信息
    var queueSnapshot: (() -> QueueSnapshot)?

    struct QueueSnapshot {
        var total: Int
        var done: Int
        var active: Int
        var pending: Int
        var isPaused: Bool
    }

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        dropView = StatusDropView()
        super.init()

        if let button = statusItem.button {
            button.image = MenuBarIcon.idle()
            button.image?.accessibilityDescription = "得意忘形"

            // 覆盖整个按钮的透明接收层。不改按钮外观，只负责收拖放。
            dropView.frame = button.bounds
            dropView.autoresizingMask = [.width, .height]
            dropView.onDrop = { [weak self] urls in self?.onDrop?(urls) }
            dropView.onClick = { [weak self] in self?.popUpMenu() }
            button.addSubview(dropView)
        }

        menu.delegate = self
        // 平时不挂 statusItem.menu：拖放层盖在按钮上，点击到不了按钮，
        // 系统那套"点按钮弹菜单"不会自己触发。只在真的要弹时临时挂上去，见 popUpMenu()。
    }

    /// 弹菜单。位置交给系统算，不自己来。
    ///
    /// 曾经是手算锚点（`menu.popUp(at: (0, button.bounds.height + 5))`，即按钮底边下方 5pt）。
    /// 外接屏上正好，带刘海的内建屏上会错位并长出滚动箭头，原因是：
    ///
    /// - 按钮高度恒为 22pt，**不随刘海变**；
    /// - 但内建屏的菜单栏是 38pt 高（`safeAreaInsets.top` = 32），外接屏只有 25pt。
    ///
    /// 于是距按钮顶端 27pt 那个锚点，在外接屏上已经出了菜单栏，在内建屏上还埋在菜单栏里。
    /// AppKit 不让菜单压住菜单栏，只好把它挪位并裁短——顶部那个 `^` 就是被裁短的证据，
    /// 得再往上移一次才能看到第一项。把 5 调大只是换一块屏出错。
    ///
    /// 临时把菜单挂到 statusItem 上再 `performClick`，位置、屏幕边界、刘海、按钮高亮
    /// 就全归系统管了，各块屏行为一致。`performClick` 会一直阻塞到菜单关闭。
    private func popUpMenu() {
        guard let button = statusItem.button else { return }
        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
    }

    /// 有图在跑时给图标换个样子，不用打开窗口也知道还在忙
    func setBusy(_ busy: Bool) {
        guard let button = statusItem.button else { return }
        button.image = busy ? MenuBarIcon.busy() : MenuBarIcon.idle()
        button.image?.accessibilityDescription = "得意忘形"
    }

    // MARK: - 菜单动作

    @objc private func openWindow() { onOpenWindow?() }
    @objc private func openSettings() { onOpenSettings?() }
    @objc private func togglePause() { onTogglePause?() }
    @objc private func importFolder() { onImportFolder?() }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
}

// MARK: - 菜单内容

extension StatusItemController: NSMenuDelegate {
    /// 每次展开重建，这样队列状态是实时的
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        add(menu, "打开得意忘形", #selector(openWindow), key: "o")
        add(menu, "导入文件夹…", #selector(importFolder), key: "i")

        menu.addItem(.separator())

        let snapshot = queueSnapshot?() ?? QueueSnapshot(
            total: 0, done: 0, active: 0, pending: 0, isPaused: false)

        let status: String
        if snapshot.total == 0 {
            status = "队列为空 · 把图拖到这个图标上"
        } else if snapshot.active > 0 {
            status = "分析中 \(snapshot.active) 张 · 已完成 \(snapshot.done)/\(snapshot.total)"
        } else if snapshot.pending > 0 {
            status = snapshot.isPaused
                ? "已暂停 · 还有 \(snapshot.pending) 张待分析"
                : "等待中 \(snapshot.pending) 张 · 已完成 \(snapshot.done)/\(snapshot.total)"
        } else {
            status = "已完成 \(snapshot.done)/\(snapshot.total)"
        }
        let info = NSMenuItem(title: status, action: nil, keyEquivalent: "")
        info.isEnabled = false
        menu.addItem(info)

        // 只在有事可做时才给暂停/继续，避免菜单里挂一堆灰按钮
        if snapshot.active > 0 || (snapshot.isPaused && snapshot.pending > 0) {
            add(menu, snapshot.isPaused ? "继续分析" : "暂停分析", #selector(togglePause), key: "")
        }

        menu.addItem(.separator())
        add(menu, "设置…", #selector(openSettings), key: ",")
        menu.addItem(.separator())
        add(menu, "退出得意忘形", #selector(quit), key: "q")
    }

    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, key: String) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }
}

// MARK: - 透明的拖放接收层

private final class StatusDropView: NSView {
    var onDrop: (([URL]) -> Void)?
    var onClick: (() -> Void)?
    private var isHighlighted = false {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isHighlighted else { return }
        NSColor.controlAccentColor.withAlphaComponent(0.3).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4).fill()
    }

    // 这层盖在状态栏按钮上面，鼠标事件先落到它这里，按钮自己收不到点击。
    // 所以由它把点击报上去，让 controller 自己弹菜单。
    //
    // 不能用 hitTest 返回 nil 放行点击——AppKit 找拖放目标时也走 hitTest，
    // 那样会把拖放一起关掉。
    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func rightMouseDown(with event: NSEvent) {
        onClick?()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let ok = !imageURLs(from: sender).isEmpty
        isHighlighted = ok
        return ok ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isHighlighted = false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isHighlighted = false
        let urls = imageURLs(from: sender)
        guard !urls.isEmpty else { return false }
        onDrop?(urls)
        return true
    }

    /// 只收图片。拖个 PDF 或文件夹进来应该被拒绝，而不是入队后再失败。
    private func imageURLs(from sender: NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier],
        ]
        let objects = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: options)
        return (objects as? [URL]) ?? []
    }
}
