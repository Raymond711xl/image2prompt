import Foundation
import Image2PromptCore
import Observation

/// 界面层的共享状态。队列本身住在 Core 里（可测），这里只负责把它和窗口接起来。
@Observable
@MainActor
final class AppState {
    let queue: AnalysisQueue
    let settings = Settings.shared

    /// 当前详情页看的是哪一条
    var selected: QueueItem?

    @ObservationIgnored var onSettingsRequested: (() -> Void)?
    @ObservationIgnored var onQuitRequested: (() -> Void)?
    @ObservationIgnored var onBusyChanged: ((Bool) -> Void)?

    private var lastBusy = false

    /// 本地库文件位置，设置页显示用。打不开时为 nil（退回纯内存运行）。
    let storePath: String?

    init() {
        let settings = Settings.shared
        // 库打不开不该让 App 起不来——降级成内存模式，并把原因显示在设置页
        let store = try? Store(url: try Store.defaultURL())
        storePath = store?.url.path
        queue = AnalysisQueue(provider: settings.makeProvider(), store: store)
        queue.autoAnalyze = settings.autoAnalyze
        queue.maxConcurrent = settings.maxConcurrent
        // 上次没跑完的接着跑。必须在设置生效之后调，否则用的是默认并发数。
        queue.resumePending()
    }

    /// 设置改了之后同步给队列
    func applySettings() {
        queue.autoAnalyze = settings.autoAnalyze
        queue.maxConcurrent = settings.maxConcurrent
        queue.setProvider(settings.makeProvider())
    }

    /// 供界面在状态变化时调用，驱动菜单栏图标的忙碌标记
    func syncBusyIndicator() {
        let busy = queue.activeCount > 0
        guard busy != lastBusy else { return }
        lastBusy = busy
        onBusyChanged?(busy)
    }
}
