import Foundation
import Observation

/// 生图任务的状态中枢。
///
/// **为什么必须存在**：生成原来跑在 `BriefSection` 的 `@State` 里，状态跟着详情页走。
/// 那样有两个后果——侧栏读不到生成进度（只有当前选中的那张图知道自己在跑），
/// 以及切换选中项时那个 `@State` 会跟着串台，另一张图也显示"生成中"。
/// 进度条和提示音都要求"谁在跑"是全局事实，所以它得从视图里搬出来。
///
/// 与 `AnalysisQueue` 分开而不是合并：分析是自动的、并发的、每张图一次；
/// 生成是手动触发的、一次只跑一个、同一张图可以跑很多次。调度规则没有一条重合。
@Observable
@MainActor
public final class GenerationQueue {

    public enum State: Equatable, Sendable {
        case idle
        case running(model: ModelId, startedAt: Date)
        case failed(String)

        public var isRunning: Bool {
            if case .running = self { return true }
            return false
        }

        public var startedAt: Date? {
            if case .running(_, let at) = self { return at }
            return nil
        }
    }

    /// 按队列条目 id 记状态。没有条目的 id 就是 `.idle`。
    public private(set) var states: [UUID: State] = [:]

    /// 每完成一次加一。界面靠它知道该重新读生成历史了——
    /// 用计数器而不是回调，是因为详情页会被反复重建，回调容易挂丢。
    public private(set) var completionTick: Int = 0

    /// 走到终态时回调一次，`success` 区分成功和失败。提示音接这里。
    @ObservationIgnored
    public var onFinished: ((UUID, Bool) -> Void)?

    private var provider: (any GenerationProvider)?
    private var task: Task<Void, Never>?
    /// 产物落在哪个根目录下。只有测试会传，正常运行走 Application Support。
    private let storeRoot: URL?

    public init(provider: (any GenerationProvider)? = nil, storeRoot: URL? = nil) {
        self.provider = provider
        self.storeRoot = storeRoot
    }

    public func setProvider(_ newProvider: (any GenerationProvider)?) {
        provider = newProvider
    }

    public var isAvailable: Bool { provider != nil }
    public var providerName: String? { provider?.displayName }

    /// 全局同时只跑一个。
    ///
    /// 不是技术限制，是成本和判断力的限制：并发生图只会同时烧额度，
    /// 而"像不像"这件事本来就得一张一张看。
    public var isBusy: Bool { task != nil }

    public func state(for itemID: UUID) -> State { states[itemID] ?? .idle }

    /// 当前在跑的是哪张图。菜单栏忙碌标记和 footer 用。
    public var runningItemID: UUID? {
        states.first { $0.value.isRunning }?.key
    }

    // MARK: - 跑

    /// 起一个生图任务。已经有任务在跑时直接忽略——按钮那边也会是禁用态，
    /// 这里再挡一次是防止快速连点插进来两个。
    public func generate(
        itemID: UUID, model: ModelId, prompt: String, aspectRatio: String
    ) {
        guard let provider, !isBusy else { return }

        states[itemID] = .running(model: model, startedAt: Date())
        let root = storeRoot

        task = Task { [weak self] in
            var ok = false
            var failure: String?
            do {
                let job = try GenerationStore.newJobDirectory(for: itemID, root: root)
                let result = try await provider.generate(
                    GenerationRequest(
                        prompt: prompt,
                        model: model,
                        aspectRatio: aspectRatio,
                        jobDirectory: job.url
                    ))
                try GenerationStore.save(
                    GenerationStore.Record(
                        jobID: job.jobID,
                        createdAt: Date(),
                        model: model,
                        prompt: result.sentPrompt,
                        finalPrompt: result.finalPrompt,
                        pixelWidth: result.pixelWidth,
                        pixelHeight: result.pixelHeight,
                        toolUsed: result.toolUsed,
                        requestedAspect: aspectRatio
                    ), in: job.url)
                ok = true
            } catch {
                failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            self?.finish(itemID: itemID, ok: ok, failure: failure)
        }
    }

    /// 放弃当前任务。`AgentRunner` 会真的把子进程杀掉，不是只放开我们这边的等待。
    ///
    /// 状态和 task 的清理留给 `finish`：进程收到 SIGTERM 之后才真的结束，
    /// 在这里就把 task 置空的话，下一次点生成会和还没死透的那个并排跑。
    public func cancel() {
        guard isBusy else { return }
        cancelling = true
        task?.cancel()
    }

    private var cancelling = false

    private func finish(itemID: UUID, ok: Bool, failure: String?) {
        task = nil
        let wasCancelled = cancelling
        cancelling = false

        if wasCancelled {
            // 人就在跟前按的取消，不用再响一声告诉他
            states[itemID] = .failed("已取消")
            return
        }

        states[itemID] = ok ? .idle : .failed(failure ?? "生成失败")
        completionTick += 1
        onFinished?(itemID, ok)
    }

    /// 清掉某条的失败提示（用户看过了、或者重新开始跑）
    public func clearError(for itemID: UUID) {
        if case .failed = state(for: itemID) { states[itemID] = .idle }
    }

    /// 条目被移出队列时顺手清掉，免得状态字典无限长
    public func forget(itemID: UUID) {
        states[itemID] = nil
    }
}
