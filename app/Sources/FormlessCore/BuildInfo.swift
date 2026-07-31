import Foundation

/// A0 阶段的占位内容：让 Core 这个 target 有源文件可编，并给壳 App 一点可显示的东西。
/// A1 开始，这个文件周围会长出 StyleSpec / Compile / Lint / Drift。
public enum BuildInfo {
    /// 与 schema/stylespec.v0.2.json 对应的版本号。移植 StyleSpec 时这里要跟着走。
    public static let styleSpecVersion = "0.2"

    /// 当前里程碑。A0 = 只证明构建链路通了，没有任何业务逻辑。
    public static let milestone = "A0"
}
