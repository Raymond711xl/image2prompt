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
    public let id: UUID
    public let imageURL: URL
    public let addedAt: Date
    public internal(set) var status: AnalysisStatus = .waiting
    public internal(set) var spec: StyleSpec?

    /// 用户随手写的「这次要生成什么」原文。留着不丢——解析可能出错，原文是唯一真相。
    public var briefText: String = ""
    /// briefText 解析出来的结构化结果，用户可以继续改
    public var brief: Brief?

    public var fileName: String { imageURL.lastPathComponent }

    /// 图还在不在。原图只读，被移走了只标记，不擅自处理。
    public var imageExists: Bool {
        FileManager.default.isReadableFile(atPath: imageURL.path)
    }

    public init(id: UUID = UUID(), imageURL: URL, addedAt: Date = Date()) {
        self.id = id
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
    /// 落库。为 nil 时纯内存运行（测试用）。
    private let store: Store?

    public init(provider: any VisionProvider, store: Store? = nil) {
        self.provider = provider
        self.store = store
        if let store {
            // 上次退出时「分析中」的条目会被 Store 读回成「等待」——
            // 进程都没了，那次分析不可能跑完
            items = (try? store.loadAll()) ?? []
        }
    }

    /// 写回单条。存不进去不该让界面崩，但要留下痕迹。
    private func persist(_ item: QueueItem) {
        guard let store else { return }
        do {
            try store.upsert(item)
        } catch {
            lastStoreError = error.localizedDescription
        }
    }

    /// 最近一次落库失败的原因，界面可以据此提示
    public private(set) var lastStoreError: String?

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
        new.forEach(persist)

        if autoAnalyze { pump() }
        return new
    }

    /// 把用户改过的 Brief 写回磁盘。界面编辑后调用。
    public func persistBrief(_ item: QueueItem) {
        persist(item)
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
        persist(item)
        pump()
    }

    public func retryAllFailed() {
        for item in items where item.status.isTerminal {
            if case .failed = item.status {
                item.status = .waiting
                persist(item)
            }
        }
        pump()
    }

    public func remove(_ item: QueueItem) {
        running[item.id]?.cancel()
        running[item.id] = nil
        items.removeAll { $0.id == item.id }
        try? store?.delete(id: item.id)
    }

    public func clearCompleted() {
        let removed = items.filter { $0.status == .done }
        items = items.filter { $0.status != .done }
        for item in removed { try? store?.delete(id: item.id) }
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
        // 「分析中」刻意不落库——Store 会把它存成「等待」，
        // 这样进程被杀掉后重开，这条会回到等待而不是卡在转圈
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
        persist(item)
        pump()
    }
}
