import FormlessCore
import SwiftUI

/// 长任务的进度条。分析和生成共用。
///
/// **这条进度是推算的，不是测出来的**——底层是 `codex exec` 这类一次性子进程，
/// 跑完之前不吐任何百分比。所以这个组件有两条不能破的规矩（`Pace` 里也写了）：
///
/// - 条子封顶 92%，永远不假装完成；
/// - 条子旁边必须同时显示**真实已用时**。跑超预期时条不动、数字继续涨，
///   一眼看得出"这次比平常慢"，而不是对着一条卡在 92% 的条猜。
///
/// 用 `TimelineView` 而不是 Timer：视图自己按秒重算，不用管定时器的生命周期，
/// 窗口关掉也不会留下一个还在跑的 timer。
struct TaskProgress: View {
    let startedAt: Date
    let expected: TimeInterval
    let tint: Color
    let label: String
    let icon: String
    /// 侧栏里空间紧，只留一行 + 细条；详情页可以铺开
    var compact: Bool = true

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(startedAt))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: compact ? 9 : 10))
                        .foregroundStyle(tint)
                    Text(label)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    // 等宽数字：秒数跳动时不会让整行左右抖
                    Text("\(Pace.clock(elapsed)) / 约 \(Pace.clock(expected))")
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
                .font(.system(size: compact ? 10 : 11))

                ProgressView(value: Pace.fraction(elapsed: elapsed, expected: expected))
                    .progressViewStyle(.linear)
                    .tint(tint)
                    .frame(height: 3)
            }
        }
    }
}
