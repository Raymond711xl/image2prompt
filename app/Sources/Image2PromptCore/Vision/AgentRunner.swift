import Foundation

/// 跑一条本地 agent 命令，把它的标准输出拿回来。
///
/// 除了识图，以后 Brief 解析和 drift 推理也走这里——凡是"发一段指令、收一段文字"
/// 的活都能复用，不用再各写一遍进程管理。
public enum AgentRunner {

    public enum AgentError: Error, LocalizedError {
        case executableNotFound(String)
        case launchFailed(String)
        case timedOut(TimeInterval)
        case nonZeroExit(code: Int32, stderr: String)
        case cancelled

        public var errorDescription: String? {
            switch self {
            case .executableNotFound(let name):
                return "找不到可执行文件「\(name)」。请在设置里填绝对路径，或确认它已安装。"
            case .launchFailed(let detail):
                return "启动失败：\(detail)"
            case .timedOut(let seconds):
                return "超过 \(Int(seconds)) 秒没有返回，已中止"
            case .nonZeroExit(let code, let stderr):
                let tail = stderr.suffix(400)
                return "agent 退出码 \(code)\(tail.isEmpty ? "" : "：\(tail)")"
            case .cancelled:
                return "已取消"
            }
        }
    }

    // MARK: - 可执行文件查找

    /// GUI 启动的 App **不继承登录 shell 的 PATH**（只有 /usr/bin:/bin:/usr/sbin:/sbin），
    /// 所以装在 ~/.npm-global/bin 或 /opt/homebrew/bin 的 agent 直接找不到。
    /// 这是双击运行和终端运行行为不一致的最常见原因，必须自己补查找路径。
    static let searchPaths: [String] = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/.npm-global/bin",
            "\(home)/.local/bin",
            "\(home)/.bun/bin",
            "\(home)/.cargo/bin",
            "\(home)/bin",
            "/usr/bin",
            "/bin",
        ]
    }()

    public static func resolveExecutable(_ nameOrPath: String) throws -> URL {
        let fm = FileManager.default
        let trimmed = nameOrPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AgentError.executableNotFound(nameOrPath) }

        // 绝对路径直接用
        if trimmed.hasPrefix("/") {
            guard fm.isExecutableFile(atPath: trimmed) else {
                throw AgentError.executableNotFound(trimmed)
            }
            return URL(fileURLWithPath: trimmed)
        }

        // 先查环境 PATH（从终端启动时有用），再查常见安装位置
        let envPaths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
            .map(String.init)
        for dir in envPaths + searchPaths {
            let candidate = (dir as NSString).appendingPathComponent(trimmed)
            if fm.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        throw AgentError.executableNotFound(trimmed)
    }

    // MARK: - 执行

    public static func run(preset: AgentPreset, prompt: String) async throws -> String {
        let executable = try resolveExecutable(preset.executable)
        let args = preset.resolvedArguments(prompt: prompt)
        let stdinData = preset.promptViaStdin ? Data(prompt.utf8) : nil

        return try await withTaskCancellationHandler {
            try await runProcess(
                executable: executable,
                arguments: args,
                stdin: stdinData,
                timeout: preset.timeout
            )
        } onCancel: {
            // 取消由 runProcess 内部的 state box 处理
        }
    }

    /// Process 的回调来自任意线程，用一个加锁的 box 同时收口三件事：
    /// 输出缓冲、错误缓冲、以及"只恢复一次 continuation"的保证。
    private final class RunState: @unchecked Sendable {
        private let lock = NSLock()
        private var finished = false
        private var out = Data()
        private var err = Data()
        var process: Process?

        /// 返回 true 表示这次是第一次收尾，调用方可以恢复 continuation
        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if finished { return false }
            finished = true
            return true
        }

        func appendOut(_ data: Data) {
            lock.lock()
            out.append(data)
            lock.unlock()
        }

        func appendErr(_ data: Data) {
            lock.lock()
            err.append(data)
            lock.unlock()
        }

        func drain() -> (out: String, err: String) {
            lock.lock()
            defer { lock.unlock() }
            return (
                String(data: out, encoding: .utf8) ?? "",
                String(data: err, encoding: .utf8) ?? ""
            )
        }
    }

    private static func runProcess(
        executable: URL, arguments: [String], stdin: Data?, timeout: TimeInterval
    ) async throws -> String {
        let state = RunState()

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments

            // 补上 PATH，agent 自己可能还要调别的工具
            var env = ProcessInfo.processInfo.environment
            let existing = env["PATH"] ?? ""
            env["PATH"] = (searchPaths + [existing]).joined(separator: ":")
            process.environment = env

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe
            if stdin != nil { process.standardInput = Pipe() }

            state.process = process

            // 边跑边收，避免管道缓冲区写满导致子进程阻塞
            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty { state.appendOut(data) }
            }
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty { state.appendErr(data) }
            }

            process.terminationHandler = { proc in
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil

                // 必须再同步收一次尾巴：进程退得快时，terminationHandler 可能早于
                // 最后一次 readabilityHandler 触发，那块数据就丢了。
                // 表现出来是"输出偶尔被截断"，下游报"找不到 JSON"，且难以复现。
                state.appendOut(outPipe.fileHandleForReading.readDataToEndOfFile())
                state.appendErr(errPipe.fileHandleForReading.readDataToEndOfFile())

                guard state.claim() else { return }
                let (out, err) = state.drain()

                if proc.terminationStatus == 0 {
                    continuation.resume(returning: out)
                } else {
                    continuation.resume(
                        throwing: AgentError.nonZeroExit(
                            code: proc.terminationStatus,
                            stderr: err.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
            }

            do {
                try process.run()
            } catch {
                if state.claim() {
                    continuation.resume(throwing: AgentError.launchFailed(error.localizedDescription))
                }
                return
            }

            if let stdin, let pipe = process.standardInput as? Pipe {
                DispatchQueue.global(qos: .utility).async {
                    pipe.fileHandleForWriting.write(stdin)
                    try? pipe.fileHandleForWriting.close()
                }
            }

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                guard process.isRunning else { return }
                process.terminate()
                if state.claim() {
                    continuation.resume(throwing: AgentError.timedOut(timeout))
                }
            }
        }
    }
}
