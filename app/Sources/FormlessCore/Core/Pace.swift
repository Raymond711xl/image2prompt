import Foundation

/// 一次任务通常要跑多久。**这是经验值，不是承诺。**
///
/// 底层是 `codex exec` 这类一次性子进程，跑完之前不吐任何进度百分比——
/// 界面上那条进度条只能按这里的经验时长推。所以有两条硬规矩：
///
/// 1. 条子**永远不走到满格**（见 `fraction`），封顶 92%。走满了却还没结束，
///    进度条就变成了骗人的东西，用户下次不会再信它。
/// 2. 条子旁边必须同时显示**真实已用时**。跑超预期时条不动、数字继续涨，
///    一眼能看出"这次比平常慢"。
///
/// 数值来源：识图实测约 2~3 分钟（见设置页说明），生图实测 3~4 分钟
/// （见 `docs/codex-imagegen.md`）。取偏保守的中位数，宁可条走得慢一点。
public enum Pace {
    public static let analysis: TimeInterval = 150
    public static let generation: TimeInterval = 210

    /// 已用时换算成进度。封顶 0.92，不假装完成。
    public static func fraction(elapsed: TimeInterval, expected: TimeInterval) -> Double {
        guard expected > 0 else { return 0 }
        return min(0.92, max(0.02, elapsed / expected))
    }

    /// "2:13" —— 秒数转成分:秒，超过一小时也不换算成时分，跑到那份上本身就是异常
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
