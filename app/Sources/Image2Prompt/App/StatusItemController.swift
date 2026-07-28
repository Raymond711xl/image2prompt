import AppKit
import UniformTypeIdentifiers

/// 菜单栏图标本身就是投放目标：拖图上去直接接收。
///
/// 这是 A1 的核心交互，也是整个 App 存在的理由——比"打开窗口再拖进去"少两步。
/// 必须走 AppKit：SwiftUI 的 MenuBarExtra 不暴露底层 NSStatusItem，注册不了拖放类型。
///
/// 更进一步的"拖动时自动弹出接收框"（Yoink 那种）需要全局监听拖拽会话开始，
/// 留到后续里程碑。现在是标准做法：图标常驻，拖上去即接收。
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let dropView: StatusDropView

    var onDrop: (([URL]) -> Void)?
    var onClick: (() -> Void)?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        dropView = StatusDropView()
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "wand.and.stars", accessibilityDescription: "Image to Prompt")
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(clicked)

            // 覆盖整个按钮的透明接收层。不改按钮外观，只负责收拖放。
            dropView.frame = button.bounds
            dropView.autoresizingMask = [.width, .height]
            dropView.onDrop = { [weak self] urls in self?.onDrop?(urls) }
            button.addSubview(dropView)
        }
    }

    @objc private func clicked() {
        onClick?()
    }

    /// 有图在跑时给图标加个角标，不用打开窗口也知道还在忙
    func setBusy(_ busy: Bool) {
        guard let button = statusItem.button else { return }
        let name = busy ? "wand.and.stars.inverse" : "wand.and.stars"
        button.image = NSImage(systemSymbolName: name, accessibilityDescription: "Image to Prompt")
        button.image?.isTemplate = true
    }
}

/// 透明的拖放接收层
private final class StatusDropView: NSView {
    var onDrop: (([URL]) -> Void)?
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
