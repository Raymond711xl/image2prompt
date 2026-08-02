import Foundation
import ImageIO

/// 分析指令：把 SKILL.md 模式 A 的方法论编成一份会产出合法 StyleSpec 的指令。
///
/// 它是**所有** VisionProvider 的共同输入——本地 agent 收到的是它，
/// 以后接 API 时它就是系统提示词。规则只有一份，换引擎不换方法论。
public enum AnalyzePrompt {

    public enum PromptError: Error, LocalizedError {
        case missingResource(String)

        public var errorDescription: String? {
            switch self {
            case .missingResource(let name):
                return "打包里找不到资源：\(name)"
            }
        }
    }

    /// schema 随 .app 一起分发，agent 用得到的是这个真实磁盘路径
    public static func schemaURL() throws -> URL {
        guard let url = Bundle.module.url(forResource: "stylespec.v0.2", withExtension: "json")
        else {
            throw PromptError.missingResource("stylespec.v0.2.json")
        }
        return url
    }

    public static func template() throws -> String {
        guard let url = Bundle.module.url(forResource: "analyze-prompt", withExtension: "md") else {
            throw PromptError.missingResource("analyze-prompt.md")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// 精确像素宽高，App 自己读文件属性，不委托给 agent。
    ///
    /// 早期版本让分析 agent 自己跑 shell 工具（`sips`）量。App 里的 Claude Code 预设锁了
    /// `--allowed-tools Read`（刻意的限制，换更快更稳），指令要求它跑 shell 命令、权限又不让跑，
    /// agent 会在这上面卡壳——拖慢分析，还可能顺带搞坏输出。这类确定性计算本来就不该麻烦模型，
    /// App 自己读一次图片属性（不启子进程、不用额外权限，和生成缩略图走的是同一条路），
    /// 把量好的数字直接喂给 agent，agent 只管抄。
    static func pixelDimensions(of url: URL) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = props[kCGImagePropertyPixelWidth] as? Int,
            let height = props[kCGImagePropertyPixelHeight] as? Int,
            width > 0, height > 0
        else { return nil }
        return (width, height)
    }

    /// 填好图片路径、schema 路径和精确画幅的完整指令
    public static func build(imageURL: URL) throws -> String {
        let dimensionsNote: String
        if let (width, height) = pixelDimensions(of: imageURL) {
            let aspect = Double(width) / Double(height)
            dimensionsNote = String(
                format: "已经量好：%d×%d，aspect_exact=%.4f。直接抄这三个值，"
                    + "不需要你自己测量或调用 shell 工具",
                width, height, aspect)
        } else {
            dimensionsNote =
                "App 没能自动读出像素尺寸（文件可能损坏或格式不支持）。"
                + "source.width/height 如实标注最接近的整数并写进 confidence.uncertain_fields，"
                + "不要为了填满字段编造精确值"
        }

        return try template()
            .replacingOccurrences(of: "{{IMAGE_PATH}}", with: imageURL.path)
            .replacingOccurrences(of: "{{SCHEMA_PATH}}", with: try schemaURL().path)
            .replacingOccurrences(of: "{{EXACT_DIMENSIONS}}", with: dimensionsNote)
    }
}
