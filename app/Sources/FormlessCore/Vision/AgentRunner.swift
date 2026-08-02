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

        let state = RunState()
        return try await withTaskCancellationHandler {
            try await runProcess(
                state: state,
                executable: executable,
                arguments: args,
                stdin: stdinData,
                timeout: preset.timeout
            )
        } onCancel: {
            state.cancel()
        }
    }

    /// 通用入口：跑任意命令行，收标准输出。
    ///
    /// `AgentPreset` 那条口子假设"参数模板里塞一段提示词"，生图不是这个形状——
    /// 它要一串固定 flag、一个工作目录，提示词走 stdin，结果走文件。
    /// 所以在 preset 之外单开一个入口，进程管理（PATH 补全、超时、边跑边收、
    /// 退出码收口）仍然共用下面同一份实现。
    public static func run(
        executable: String,
        arguments: [String],
        stdin: String? = nil,
        timeout: TimeInterval,
        currentDirectory: URL? = nil
    ) async throws -> String {
        let url = try resolveExecutable(executable)
        let state = RunState()
        return try await withTaskCancellationHandler {
            try await runProcess(
                state: state,
                executable: url,
                arguments: arguments,
                stdin: stdin.map { Data($0.utf8) },
                timeout: timeout,
                currentDirectory: currentDirectory
            )
        } onCancel: {
            state.cancel()
        }
    }

    /// Process 的回调来自任意线程，用一个加锁的 box 同时收口三件事：
    /// 输出缓冲、错误缓冲、以及"只恢复一次 continuation"的保证。
    private final class RunState: @unchecked Sendable {
        private let lock = NSLock()
        private var finished = false
        private var out = Data()
        private var err = Data()
        private var process: Process?
        private var launched = false
        private var cancelled = false

        /// 返回 true 表示这次是第一次收尾，调用方可以恢复 continuation
        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if finished { return false }
            finished = true
            return true
        }

        /// 把进程交给 box 保管。返回 true 表示在启动之前就已经被取消了，
        /// 调用方不该再 run()——起来了也是白烧一次额度。
        func attach(_ newProcess: Process) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            process = newProcess
            return cancelled
        }

        /// 进程真的起来了。**必须在 `process.run()` 之后调**：
        /// 对没启动过的 Process 调 terminate() 会直接抛 ObjC 异常，整个进程崩掉。
        func markLaunched() {
            lock.lock()
            let alreadyCancelled = cancelled
            launched = true
            let running = process
            lock.unlock()
            // run() 和 cancel() 撞在一起时，取消先到、terminate 被跳过，这里补一刀
            if alreadyCancelled, let running, running.isRunning { running.terminate() }
        }

        /// 杀掉子进程。
        ///
        /// 不杀的话，取消只是放开了我们这边的等待：`codex` 还在后台跑、额度照烧，
        /// 而队列已经以为自己空闲了，下一次点生成会并排再起一个。
        func cancel() {
            lock.lock()
            cancelled = true
            let target = launched ? process : nil
            lock.unlock()
            if let target, target.isRunning { target.terminate() }
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
        state: RunState,
        executable: URL, arguments: [String], stdin: Data?, timeout: TimeInterval,
        currentDirectory: URL? = nil
    ) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            if let currentDirectory { process.currentDirectoryURL = currentDirectory }

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

            // 交给 box 保管，取消时才有东西可杀
            if state.attach(process) {
                if state.claim() { continuation.resume(throwing: AgentError.cancelled) }
                return
            }

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
                state.markLaunched()
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
