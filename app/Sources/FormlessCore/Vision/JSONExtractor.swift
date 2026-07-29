import Foundation

/// 从 agent 的混杂输出里挖出那个 JSON 对象。
///
/// 指令里已经写了"只输出 JSON、不要围栏"，但 agent 不是 API——它会加前言、
/// 包代码块、末尾补一句"已完成"。与其指望它每次都听话，不如在这边稳稳地取。
public enum JSONExtractor {

    public enum ExtractError: Error, LocalizedError {
        case noJSONFound(rawTail: String)

        public var errorDescription: String? {
            switch self {
            case .noJSONFound(let tail):
                return "agent 的输出里没有找到 JSON 对象。末尾内容：\(tail)"
            }
        }
    }

    /// 扫描出第一个大括号平衡的 JSON 对象。
    /// 逐字符扫而不是用正则：JSON 里嵌套对象和带转义的字符串都会让正则失效。
    public static func extract(from raw: String) throws -> Data {
        let scalars = Array(raw.unicodeScalars)
        var index = 0

        while index < scalars.count {
            guard scalars[index] == "{" else {
                index += 1
                continue
            }
            if let end = balancedEnd(scalars, from: index) {
                let slice = String(String.UnicodeScalarView(scalars[index...end]))
                let data = Data(slice.utf8)
                // 必须真的能解析成对象才算数——顺手排除了正文里偶然出现的花括号
                if (try? JSONSerialization.jsonObject(with: data)) is [String: Any] {
                    return data
                }
            }
            index += 1
        }

        let tail = String(raw.suffix(300)).trimmingCharacters(in: .whitespacesAndNewlines)
        throw ExtractError.noJSONFound(rawTail: tail)
    }

    /// 从 `start`（一个 `{`）找到与之配对的 `}`，跳过字符串字面量里的括号
    private static func balancedEnd(_ scalars: [Unicode.Scalar], from start: Int) -> Int? {
        var depth = 0
        var inString = false
        var escaped = false

        for i in start..<scalars.count {
            let c = scalars[i]

            if inString {
                if escaped {
                    escaped = false
                } else if c == "\\" {
                    escaped = true
                } else if c == "\"" {
                    inString = false
                }
                continue
            }

            switch c {
            case "\"": inString = true
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 { return i }
            default: break
            }
        }
        return nil
    }
}
