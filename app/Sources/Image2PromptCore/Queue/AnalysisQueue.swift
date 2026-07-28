import Foundation
import Observation

public enum AnalysisStatus: Equatable, Sendable {
    case waiting
    case analyzing
    case done
    case failed(String)

    public var isTerminal: Bool {
        switch self {
        case .done, .failed: return true
        case .waiting, .analyzing: return false
        }
    }

    public var label: String {
        switch self {
        case .waiting: return "等待"
        case .analyzing: return "分析中"
        case .done: return "完成"
        case .failed: return "失败"
        }
    }
}

@Observable
public final class QueueItem: Identifiable, @unchecked Sendable {
    public let id = UUID()
    public let imageURL: URL
    public let addedAt: Date
    public internal(set) var status: AnalysisStatus = .waiting
    public internal(set) var spec: StyleSpec?

    public var fileName: String { imageURL.lastPathComponent }

    public init(imageURL: URL, addedAt: Date = Date()) {
        self.imageURL = imageURL
        self.addedAt = addedAt
    }
}

// 按引用身份比较：同一条目就是同一条目，状态变化不影响相等性。
// List(selection:) 需要 Hashable，值语义在这里反而是错的——
// 用内容比较的话，两条状态相同的记录会被当成同一条。
extension QueueItem: Hashable {
    public static func == (lhs: QueueItem, rhs: QueueItem) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// 待办队列：拖进来的图排队等分析。
///
/// 拆成独立类型而不是塞进 View，是因为并发控制、暂停恢复、失败重试这些行为
/// 必须能在没有界面的情况下被测试——UI 里跑不出竞态。
@Observable
@MainActor
public final class AnalysisQueue {
    public private(set) var items: [QueueItem] = []
    /// 关掉后拖进来的图只入队不自动跑，等用户手动点。设置里可切换。
    public var autoAnalyze: Bool = true
    /// 暂停：不再启动新任务，已在飞的让它跑完
    public private(set) var isPaused: Bool = false
    /// 同时最多跑几个
    public var maxConcurrent: Int = 3

    private var provider: any VisionProvider
    private var running: [UUID: Task<Void, Never>] = [:]

    public init(provider: any VisionProvider) {
        self.provider = provider
    }

    public func setProvider(_ newProvider: any VisionProvider) {
        provider = newProvider
    }

    public var activeCount: Int { running.count }

    public var pendingCount: Int {
        items.filter { $0.status == .waiting }.count
    }

    public var doneCount: Int {
        items.filter { $0.status == .done }.count
    }

    // MARK: - 入队

    @discardableResult
    public func enqueue(_ urls: [URL]) -> [QueueItem] {
        // 同一张图重复拖入直接忽略，不产生重复条目
        let existing = Set(items.map(\.imageURL.standardizedFileURL))
        let fresh = urls
            .map(\.standardizedFileURL)
            .filter { !existing.contains($0) }

        let new = fresh.map { QueueItem(imageURL: $0) }
        items.append(contentsOf: new)

        if autoAnalyze { pump() }
        return new
    }

    // MARK: - 控制

    public func pause() {
        isPaused = true
    }

    public func resume() {
        isPaused = false
        pump()
    }

    /// 手动开跑（autoAnalyze 关闭时用）
    public func startPending() {
        isPaused = false
        pump()
    }

    public func retry(_ item: QueueItem) {
        guard case .failed = item.status else { return }
        item.status = .waiting
        pump()
    }

    public func retryAllFailed() {
        for item in items where item.status.isTerminal {
            if case .failed = item.status { item.status = .waiting }
        }
        pump()
    }

    public func remove(_ item: QueueItem) {
        running[item.id]?.cancel()
        running[item.id] = nil
        items.removeAll { $0.id == item.id }
    }

    public func clearCompleted() {
        let keep = items.filter { $0.status != .done }
        items = keep
    }

    // MARK: - 调度

    /// 把空闲槽位填满。所有状态变更都经过这里，不散落在各处。
    private func pump() {
        guard !isPaused else { return }
        while running.count < maxConcurrent,
            let next = items.first(where: { $0.status == .waiting })
        {
            start(next)
        }
    }

    private func start(_ item: QueueItem) {
        item.status = .analyzing
        let provider = self.provider
        let url = item.imageURL

        // Task 继承 @MainActor 隔离，所以 finish 不需要 await。
        // provider.analyze 是 nonisolated async，会跳到协作线程池执行，不占主线程。
        running[item.id] = Task { [weak self] in
            do {
                let spec = try await provider.analyze(imageURL: url)
                self?.finish(item, result: .success(spec))
            } catch {
                self?.finish(item, result: .failure(error))
            }
        }
    }

    private func finish(_ item: QueueItem, result: Result<StyleSpec, Error>) {
        running[item.id] = nil
        switch result {
        case .success(let spec):
            item.spec = spec
            item.status = .done
        case .failure(let error):
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            item.status = .failed(message)
        }
        pump()
    }
}
