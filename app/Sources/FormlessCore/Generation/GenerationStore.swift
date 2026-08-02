import Foundation

/// 生成历史落盘。
///
/// **刻意不进 SQLite。** 每次生成的产物是一整个目录（图 + agent 的 result.json +
/// 我们发出去的 instruction.txt + schema），本来就是文件；塞进库要么只存路径
/// （那库里那行就是冗余），要么把二进制灌进去（那备份和排查都变难）。
/// 目录即记录，列表就是枚举目录——顺带省掉一次 schema 迁移。
///
/// 每次生成一个独立目录还有一个硬理由：**并发隔离**。Codex 把图先落在
/// `~/.codex/generated_images/<session-uuid>/`，App 不能去猜"最新的一张"，
/// 只能让它复制到本次任务唯一的固定路径。
public enum GenerationStore {

    /// 一次生成的完整记录
    public struct Record: Sendable, Hashable, Identifiable, Codable {
        public var id: String { jobID }
        public let jobID: String
        public let createdAt: Date
        public let model: ModelId
        /// 我们实际发出去的提示词（编译器产出 + 一句画幅）
        public let prompt: String
        /// agent 自述实际用的提示词
        public let finalPrompt: String?
        public let pixelWidth: Int
        public let pixelHeight: Int
        public let toolUsed: String?
        /// 这次要的画幅，如 "3:4"。内置模式下画幅是软约束，要能看出中没中。
        public let requestedAspect: String?

        enum CodingKeys: String, CodingKey {
            case jobID = "job_id"
            case createdAt = "created_at"
            case model, prompt
            case finalPrompt = "final_prompt"
            case pixelWidth = "pixel_width"
            case pixelHeight = "pixel_height"
            case toolUsed = "tool_used"
            case requestedAspect = "requested_aspect"
        }

        public init(
            jobID: String, createdAt: Date, model: ModelId, prompt: String,
            finalPrompt: String?, pixelWidth: Int, pixelHeight: Int, toolUsed: String?,
            requestedAspect: String? = nil
        ) {
            self.jobID = jobID
            self.createdAt = createdAt
            self.model = model
            self.prompt = prompt
            self.finalPrompt = finalPrompt
            self.pixelWidth = pixelWidth
            self.pixelHeight = pixelHeight
            self.toolUsed = toolUsed
            self.requestedAspect = requestedAspect
        }

        /// 提示词有没有被中间环节改写。false 时这张图不能用来评判编译器。
        public var promptIsVerbatim: Bool { finalPrompt == prompt }
        public var pixelSize: String { "\(pixelWidth)×\(pixelHeight)" }
        /// 走的不是内置 image_gen 时值得提醒——skill 描述会被截断，触发不是必然。
        public var usedBuiltinTool: Bool { toolUsed == "builtin_image_gen" }

        /// 出图画幅有没有中。
        ///
        /// 内置 `image_gen` 没有尺寸参数，画幅只能靠提示词里那句话软约束，模型可能不听
        /// （实测要 3:4 拿到过 1254×1254 方图）。中没中要能一眼看出来，
        /// 否则拿这张图去量构图数据就是错的。nil 表示没要求或比例解析不了。
        public var aspectMatches: Bool? {
            guard let requestedAspect,
                let want = CodexImageProvider.parseRatio(requestedAspect),
                pixelHeight > 0
            else { return nil }
            let got = Double(pixelWidth) / Double(pixelHeight)
            // 5% 容差：标准档位很少能正好落在要的比例上
            return abs(got - want) / want <= 0.05
        }
    }

    // MARK: - 路径

    /// `~/Library/Application Support/<bundleid>/Generations/`
    public static func rootDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        let dir =
            base
            .appendingPathComponent(AppIdentity.bundleID, isDirectory: true)
            .appendingPathComponent("Generations", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// `root` 只给测试用：不显式换个临时根，测试就会往真实的 Application Support
    /// 里写目录。刻意做成参数而不是全局开关——全局可变状态会在并行测试之间互相踩。
    public static func directory(for itemID: UUID, root: URL? = nil) throws -> URL {
        let base = try root ?? rootDirectory()
        let dir = base.appendingPathComponent(itemID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 本次任务的唯一目录。名字带时间戳只是为了肉眼可读，唯一性靠 UUID。
    public static func newJobDirectory(for itemID: UUID, root: URL? = nil) throws -> (
        url: URL, jobID: String
    ) {
        let stamp = Self.stampFormatter.string(from: Date())
        let jobID = "\(stamp)-\(UUID().uuidString.prefix(8))"
        let url = try directory(for: itemID, root: root)
            .appendingPathComponent(jobID, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return (url, jobID)
    }

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    // MARK: - 读写

    public static func save(_ record: Record, in jobDirectory: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(record).write(to: jobDirectory.appendingPathComponent("meta.json"))
    }

    /// 某张图的全部生成历史，新的在前。读不出 meta 的目录直接跳过——
    /// 半截任务（跑失败、跑到一半退出）留下的目录不该显示成一条记录。
    public static func history(for itemID: UUID, root: URL? = nil) -> [(
        record: Record, imageURL: URL
    )] {
        guard let dir = try? directory(for: itemID, root: root),
            let entries = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil)
        else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return
            entries
            .compactMap { jobDir -> (Record, URL)? in
                let image = jobDir.appendingPathComponent("result.png")
                guard FileManager.default.fileExists(atPath: image.path),
                    let data = try? Data(contentsOf: jobDir.appendingPathComponent("meta.json")),
                    let record = try? decoder.decode(Record.self, from: data)
                else { return nil }
                return (record, image)
            }
            .sorted { $0.0.createdAt > $1.0.createdAt }
    }

    public static func delete(jobID: String, for itemID: UUID) {
        guard let dir = try? directory(for: itemID) else { return }
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(jobID))
    }
}
