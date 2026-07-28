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

    init() {
        let settings = Settings.shared
        queue = AnalysisQueue(provider: settings.makeProvider())
        queue.autoAnalyze = settings.autoAnalyze
        queue.maxConcurrent = settings.maxConcurrent
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
