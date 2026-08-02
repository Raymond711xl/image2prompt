import AppKit
import FormlessCore

/// 完成提示音。
///
/// 存在的理由很直白：一张图分析要 2~3 分钟、生成要 3~4 分钟，没人会盯着屏幕等。
/// 提示音是这个 App 唯一能在你切走之后把你叫回来的通道。
///
/// 三个音是"亲戚"（同一套音色，音高和音数不同），不看屏幕也能分清是哪件事结束了：
/// 分析完成一声、生成完成两声上行、失败两声下行。
///
/// 放在可执行 target 而不是 Core：Core 不能依赖 AppKit，队列逻辑要能在没有窗口的
/// 情况下跑测试。Core 只负责在终态调回调，响不响、响什么由这里决定。
@MainActor
enum Chime {
    enum Kind: String, CaseIterable {
        case analyze = "chime-analyze"
        case generate = "chime-generate"
        case fail = "chime-fail"
    }

    /// 预加载，别等到要响的时候才读盘——NSSound 首次播放会有可闻的延迟。
    private static var sounds: [Kind: NSSound] = {
        var loaded: [Kind: NSSound] = [:]
        for kind in Kind.allCases {
            guard let url = soundURL(kind.rawValue),
                let sound = NSSound(contentsOf: url, byReference: false)
            else { continue }
            loaded[kind] = sound
        }
        return loaded
    }()

    /// 找资源文件。
    ///
    /// 先手动查嵌套的资源包，最后才轮到 `Bundle.module`：**后者找不到东西时是
    /// fatalError，不是返回 nil**，一个提示音没打进包不该让整个 App 崩掉。
    /// SwiftPM 把资源放进 `<包名>_<target名>.bundle`，打包脚本原样搬进
    /// Contents/Resources（见 Scripts/bundle.sh），所以这条路径在装好的 App
    /// 和 .build/debug 下都成立。
    private static func soundURL(_ name: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: "wav") { return url }
        if let nested = Bundle.main.resourceURL?
            .appendingPathComponent("Formless_Formless.bundle"),
            let bundle = Bundle(url: nested),
            let url = bundle.url(forResource: name, withExtension: "wav")
        {
            return url
        }
        return Bundle.module.url(forResource: name, withExtension: "wav")
    }

    /// 上一次响的时刻，用来做合并窗
    private static var lastPlayed: [Kind: Date] = [:]

    /// 同一种音在这个窗口内只响一次。
    ///
    /// 并发 3 张图几乎同时分析完是常态，三声叠在一起是一团糊的噪音，
    /// 反而听不出发生了什么。合并成一声。
    private static let coalesceWindow: TimeInterval = 0.25

    /// 按设置决定响不响。判断放在这里而不是调用点——
    /// 调用点有三处（分析完成、生成完成、失败），规则散出去迟早不一致。
    static func ring(_ kind: Kind) {
        let settings = Settings.shared
        let allowed: Bool
        switch kind {
        case .analyze: allowed = settings.soundOnAnalyzeDone
        case .generate: allowed = settings.soundOnGenerateDone
        case .fail: allowed = settings.soundOnFailure
        }
        guard allowed else { return }
        play(kind)
    }

    /// 不看设置直接响，设置页的「试听」用。
    static func play(_ kind: Kind) {
        guard let sound = sounds[kind] else { return }

        let now = Date()
        if let last = lastPlayed[kind], now.timeIntervalSince(last) < coalesceWindow { return }
        lastPlayed[kind] = now

        sound.volume = Float(max(0, min(1, Settings.shared.soundVolume)))
        // 还在响的时候再次 play() 会直接返回 false，先停掉才能重新触发
        if sound.isPlaying { sound.stop() }
        sound.play()
    }

    /// 失败时该响哪个：失败音开着就用失败音，关了就退回对应的完成音——
    /// 「关掉失败音」的意思是不想被区别对待，不是想被静默。
    static func ringFinish(success: Bool, isGeneration: Bool) {
        if success {
            ring(isGeneration ? .generate : .analyze)
        } else if Settings.shared.soundOnFailure {
            ring(.fail)
        } else {
            ring(isGeneration ? .generate : .analyze)
        }
    }
}
