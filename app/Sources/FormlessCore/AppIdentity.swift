import Foundation

/// 产品身份的单一事实来源。
///
/// bundle id 同时被三处当成命名空间用：`.app` 的 CFBundleIdentifier（见 Scripts/bundle.sh）、
/// Application Support 下的数据目录、Keychain 的 service。改名字的时候三处必须一起动，
/// 所以字符串只在这里出现一次。
public enum AppIdentity {
    /// 中文名，界面上所有露出的地方都用它。
    public static let displayName = "得意忘形"

    /// 英文名 = 可执行文件名 = SwiftPM 产品名。
    public static let codeName = "Formless"

    public static let bundleID = "com.raymond711xl.formless"

    /// 改名前的 id（`image2prompt` 时期）。只用于把老数据搬过来，不再写入。
    /// 确认所有机器都迁完之后可以删掉它和两处 `legacy` 分支。
    public static let legacyBundleID = "com.raymond711xl.image2prompt"
}
