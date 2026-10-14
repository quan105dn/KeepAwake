import Foundation
import Darwin

/// Quét cây tiến trình để biết Claude Code có đang làm việc / chạy tác vụ không.
///
/// Hỗ trợ mọi cách chạy: CLI trong Terminal, iTerm2, terminal VS Code/Cursor, JetBrains, và
/// extension Claude Code (chạy cùng binary `claude` ở chế độ `--input-format stream-json`).
///
/// Tín hiệu "đang làm một lượt", theo thứ tự ưu tiên:
/// 1. Transcript `<config>/projects/<cwd>/*.jsonl` (+ `subagents/`): dòng cuối là lời nhắn / kết quả
///    tool / tool_use đang chờ → đang làm; `end_turn` / `turn_duration` → đã xong.
///    Đúng cho cả extension (không chạy `caffeinate`) và CLI (`caffeinate` còn sống vài phút sau lượt).
/// 2. Không đọc được transcript → con `caffeinate` của `claude` (CLI tự chạy khi đang làm).
/// Ngoài ra: con shell có args chứa `shell-snapshots` = lệnh Bash Claude chạy (kể cả chạy nền).
enum ClaudeScanner {
    struct Session: Identifiable, Equatable {
        let id: pid_t
        let project: String
        /// Nơi chạy phiên: "iTerm2", "Terminal", "VS Code", "VS Code ext"… (nil nếu không rõ).
        var client: String?
        var working = false
        /// Tuổi (giây) của các tác vụ shell đang chạy, đã lọc theo giới hạn.
        var taskAges: [TimeInterval] = []
        var ignoredTasks = 0
        /// Giải thích quyết định, dùng cho `KeepAwake --diagnose`.
        var debug: [String] = []
        var isBusy: Bool { working || !taskAges.isEmpty }
    }

    struct Proc {
        let pid: pid_t
        let ppid: pid_t
        let name: String
        let start: Date
    }

    /// - Parameter maxTaskAge: bỏ qua tác vụ chạy lâu hơn mức này (nil = không giới hạn).
    static func scan(maxTaskAge: TimeInterval?) -> [Session] {
        let procs = allProcesses()
        let now = Date()
        var transcriptCache: [String: Transcript.State] = [:]
        var sessions: [Session] = []

        for claude in procs where isClaudeCode(claude) {
            let args = argv(of: claude.pid)
            if isHelper(args: args) { continue }
            let env = environment(of: claude.pid)
            let configDir = env["CLAUDE_CONFIG_DIR"] ?? (NSHomeDirectory() as NSString).appendingPathComponent(".claude")
            let registry = Registry.read(configDir: configDir, pid: claude.pid)
            let dir = registry?.cwd ?? cwd(of: claude.pid)
            var s = Session(id: claude.pid, project: dir.map { ($0 as NSString).lastPathComponent } ?? "Claude Code")
            s.client = clientName(entrypoint: registry?.entrypoint, termProgram: env["TERM_PROGRAM"])
            s.debug.append("args: " + args.joined(separator: " ").prefix(100))
            s.debug.append("registry: " + (registry.map { "session=\($0.sessionId) entrypoint=\($0.entrypoint ?? "-")" }
                                           ?? "none (\(configDir)/sessions/\(claude.pid).json)"))
            s.debug.append("cwd: \(dir ?? "?")")

            var caffeinate = false
            for child in procs where child.ppid == claude.pid {
                s.debug.append("child: \(child.pid) \(child.name) (\(Int(now.timeIntervalSince(child.start)))s)")
                switch child.name {
                case "caffeinate":
                    caffeinate = true
                case "zsh", "bash", "sh", "fish", "dash":
                    guard arguments(of: child.pid).contains("shell-snapshots") else { continue }
                    let age = now.timeIntervalSince(child.start)
                    if let max = maxTaskAge, age > max { s.ignoredTasks += 1 } else { s.taskAges.append(age) }
                default:
                    continue
                }
            }

            var state = Transcript.State.unknown
            if let dir {
                let projectDir = Transcript.projectDirectory(configDir: configDir, cwd: dir)
                s.debug.append("project dir: \(projectDir) [\(FileManager.default.fileExists(atPath: projectDir) ? "exists" : "MISSING")]")
                if let sessionId = registry?.sessionId {
                    // Biết chính xác phiên của tiến trình này (~/.claude/sessions/<pid>.json).
                    state = Transcript.state(ofSession: sessionId, inProjectDirectory: projectDir, now: now)
                } else if let cached = transcriptCache[projectDir] {
                    state = cached
                } else {
                    state = Transcript.state(ofProjectDirectory: projectDir, now: now)
                    transcriptCache[projectDir] = state
                }
            }
            s.debug.append("transcript state: \(state); caffeinate child: \(caffeinate); tool shells: \(s.taskAges.count) (+\(s.ignoredTasks) ignored)")
            switch state {
            case .inTurn: s.working = true
            case .idle: s.working = false
            case .unknown: s.working = caffeinate
            }
            sessions.append(s)
        }
        return sessions.sorted { $0.project < $1.project }
    }

    /// Tên và PID cha của một tiến trình.
    static func info(of pid: pid_t) -> (name: String, ppid: pid_t)? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var kp = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 4, &kp, &size, nil, 0) == 0, size > 0 else { return nil }
        var comm = kp.kp_proc.p_comm
        let name = withUnsafeBytes(of: &comm) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return (name, kp.kp_eproc.e_ppid)
    }

    static func isClaudeCode(pid: pid_t) -> Bool {
        guard let i = info(of: pid) else { return false }
        return isClaudeCode(Proc(pid: pid, ppid: i.ppid, name: i.name, start: Date()))
    }

    /// Bản native / extension: tiến trình `claude` / `claude.exe`.
    /// Bản cài qua npm: `node …/bin/claude` hoặc `node …/@anthropic-ai/claude-code/cli.js`.
    private static func isClaudeCode(_ p: Proc) -> Bool {
        if p.name == "claude" || p.name == "claude.exe" { return true }
        guard p.name == "node" else { return false }
        let args = argv(of: p.pid)
        guard args.count >= 2 else { return false }
        return (args[1] as NSString).lastPathComponent == "claude"
            || args[1].contains("@anthropic-ai/claude-code/")
    }

    /// "VS Code ext" cho extension; với CLI thì theo terminal đang chạy nó.
    private static func clientName(entrypoint: String?, termProgram: String?) -> String? {
        if let e = entrypoint, e != "cli" {
            switch e {
            case "claude-vscode": return "VS Code ext"
            case "claude-desktop": return "Claude desktop"
            default: return e.hasPrefix("sdk") ? "SDK" : e
            }
        }
        switch termProgram {
        case nil, "": return nil
        case "vscode": return "VS Code"
        case "iTerm.app": return "iTerm2"
        case "Apple_Terminal": return "Terminal"
        case "WarpTerminal": return "Warp"
        case "ghostty": return "Ghostty"
        case "WezTerm": return "WezTerm"
        case let t?: return t
        }
    }

    /// Tiến trình phụ của Claude Code, không phải một phiên làm việc (vd. cầu nối Chrome, MCP server, ugrep).
    /// Binary `claude` cũng được dùng để chạy công cụ phụ (vd. `ugrep` cho Grep), khi đó argv[0] là tên công cụ.
    private static func isHelper(args: [String]) -> Bool {
        if let first = args.first, !first.isEmpty {
            let name = (first as NSString).lastPathComponent
            if name != "node", !name.lowercased().contains("claude") { return true }
        }
        return args.contains("--chrome-native-host") || (args.count >= 3 && args[1] == "mcp" && args[2] == "serve")
    }

    private static func allProcesses() -> [Proc] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0 else { return [] }
        size += size / 8
        var buf = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.stride)
        guard sysctl(&mib, 4, &buf, &size, nil, 0) == 0 else { return [] }
        return buf.prefix(size / MemoryLayout<kinfo_proc>.stride).map { kp in
            var comm = kp.kp_proc.p_comm
            let name = withUnsafeBytes(of: &comm) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            let tv = kp.kp_proc.p_un.__p_starttime
            return Proc(pid: kp.kp_proc.p_pid, ppid: kp.kp_eproc.e_ppid, name: name,
                        start: Date(timeIntervalSince1970: TimeInterval(tv.tv_sec) + TimeInterval(tv.tv_usec) / 1e6))
        }
    }

    private static func arguments(of pid: pid_t) -> String {
        argv(of: pid).joined(separator: " ")
    }

    private static func argv(of pid: pid_t) -> [String] { procArgs(of: pid).argv }

    private static func environment(of pid: pid_t) -> [String: String] {
        var env: [String: String] = [:]
        for item in procArgs(of: pid).env {
            guard let eq = item.firstIndex(of: "=") else { continue }
            env[String(item[..<eq])] = String(item[item.index(after: eq)...])
        }
        return env
    }

    /// Đọc KERN_PROCARGS2: [argc][exec path]\0…\0[argv0]\0…[argvN]\0[env0]\0…\0\0
    private static func procArgs(of pid: pid_t) -> (argv: [String], env: [String]) {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return ([], []) }
        var buf = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0 else { return ([], []) }
        let argc = Int(buf.withUnsafeBytes { $0.load(as: Int32.self) })
        var i = MemoryLayout<Int32>.size
        while i < size, buf[i] != 0 { i += 1 }   // bỏ qua exec path
        while i < size, buf[i] == 0 { i += 1 }   // và phần đệm
        var argv: [String] = [], env: [String] = []
        while i < size {
            let start = i
            while i < size, buf[i] != 0 { i += 1 }
            if start == i { break }               // chuỗi rỗng = hết env
            let item = String(decoding: buf[start..<i], as: UTF8.self)
            if argv.count < argc { argv.append(item) } else { env.append(item) }
            i += 1
        }
        return (argv, env)
    }

    private static func cwd(of pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        var path = info.pvi_cdir.vip_path
        return withUnsafeBytes(of: &path) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }
}

/// `~/.claude/sessions/<pid>.json` do Claude Code ghi cho mỗi tiến trình đang chạy.
struct Registry {
    let sessionId: String
    let cwd: String?
    let entrypoint: String?

    static func read(configDir: String, pid: pid_t) -> Registry? {
        let path = ((configDir as NSString).appendingPathComponent("sessions") as NSString)
            .appendingPathComponent("\(pid).json")
        guard let data = FileManager.default.contents(atPath: path),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (obj["pid"] as? Int).map({ $0 == Int(pid) }) ?? true,
              let sid = obj["sessionId"] as? String, !sid.isEmpty
        else { return nil }
        return Registry(sessionId: sid, cwd: obj["cwd"] as? String, entrypoint: obj["entrypoint"] as? String)
    }
}

/// Đọc trạng thái lượt làm việc từ transcript JSONL của Claude Code.
enum Transcript {
    enum State: Equatable { case inTurn, idle, unknown }

    /// Transcript đang dở mà không được ghi thêm quá lâu (crash, chờ duyệt quyền bị bỏ quên) thì coi như đã xong.
    static let staleAfter: TimeInterval = 15 * 60

    /// `<config>/projects/<cwd, mọi ký tự không phải chữ/số thành "-">`
    static func projectDirectory(configDir: String, cwd: String) -> String {
        // Giống Claude Code: thay từng đơn vị UTF-16 không phải [A-Za-z0-9] bằng "-".
        let name = String(cwd.utf16.map { u -> Character in
            switch u {
            case 48...57, 65...90, 97...122: return Character(UnicodeScalar(u)!)
            default: return "-"
            }
        })
        return ((configDir as NSString).appendingPathComponent("projects") as NSString).appendingPathComponent(name)
    }

    /// `.inTurn` nếu có transcript (phiên chính hoặc subagent) cập nhật gần đây đang dở một lượt;
    /// `.idle` nếu thư mục có transcript nhưng không cái nào đang dở; `.unknown` nếu không có gì để đọc.
    static func state(ofProjectDirectory dir: String, now: Date) -> State {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { return .unknown }
        var sawTranscript = false, unreadable = false
        for entry in entries {
            let path = (dir as NSString).appendingPathComponent(entry)
            if entry.hasSuffix(".jsonl") {
                sawTranscript = true
                guard isRecent(path, now: now) else { continue }
                switch lastState(ofFile: path, skipSidechain: true) {
                case .inTurn: return .inTurn
                case .unknown: unreadable = true
                case .idle: break
                }
            } else if subagentsInTurn(sessionDirectory: path, now: now) {
                return .inTurn
            }
        }
        if unreadable || !sawTranscript { return .unknown }
        return .idle
    }

    /// Trạng thái của đúng một phiên: `<sessionId>.jsonl` và `<sessionId>/subagents/*.jsonl`.
    static func state(ofSession id: String, inProjectDirectory dir: String, now: Date) -> State {
        guard FileManager.default.fileExists(atPath: dir) else { return .unknown }
        let main = (dir as NSString).appendingPathComponent(id + ".jsonl")
        var mainState = State.idle   // chưa có transcript (phiên mới chưa nhận lời nhắn) = đang rảnh
        if isRecent(main, now: now) {
            mainState = lastState(ofFile: main, skipSidechain: true)
            if mainState == .inTurn { return .inTurn }
        }
        if subagentsInTurn(sessionDirectory: (dir as NSString).appendingPathComponent(id), now: now) { return .inTurn }
        return mainState   // .unknown → để bên gọi dùng `caffeinate` làm dự phòng
    }

    /// `<session>/subagents/*.jsonl`: subagent (kể cả chạy nền sau khi lượt chính đã xong).
    private static func subagentsInTurn(sessionDirectory: String, now: Date) -> Bool {
        let sub = (sessionDirectory as NSString).appendingPathComponent("subagents")
        guard isRecent(sub, now: now), let files = try? FileManager.default.contentsOfDirectory(atPath: sub) else {
            return false
        }
        for f in files where f.hasSuffix(".jsonl") {
            let p = (sub as NSString).appendingPathComponent(f)
            if isRecent(p, now: now), lastState(ofFile: p, skipSidechain: false) == .inTurn { return true }
        }
        return false
    }

    private static func isRecent(_ path: String, now: Date) -> Bool {
        guard let m = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        else { return false }
        return now.timeIntervalSince(m) < staleAfter
    }

    /// Đọc ngược từ cuối file tới dòng có ý nghĩa gần nhất. Dòng có thể rất dài (ảnh, kết quả lệnh lớn:
    /// vài MB), nên đọc từng khối 256 KB cho tới khi có dòng hoàn chỉnh, tối đa `maxScan`.
    /// Kết quả được nhớ theo (kích thước, thời điểm sửa) để không đọc lại file không đổi.
    static func lastState(ofFile path: String, skipSidechain: Bool) -> State {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = (attrs[.size] as? NSNumber)?.uint64Value,
              let mtime = attrs[.modificationDate] as? Date else { return .unknown }
        let key = "\(skipSidechain ? "m" : "s")|\(path)"
        cacheLock.lock()
        if let c = cache[key], c.size == size, c.mtime == mtime { cacheLock.unlock(); return c.state }
        cacheLock.unlock()

        let state = scanBackwards(path: path, size: size, skipSidechain: skipSidechain)
        cacheLock.lock()
        if cache.count > 512 { cache.removeAll() }
        cache[key] = (size, mtime, state)
        cacheLock.unlock()
        return state
    }

    static let maxScan: UInt64 = 64 * 1024 * 1024
    private static let chunk: UInt64 = 256 * 1024
    private static var cache: [String: (size: UInt64, mtime: Date, state: State)] = [:]
    private static let cacheLock = NSLock()

    private static func scanBackwards(path: String, size: UInt64, skipSidechain: Bool) -> State {
        guard size > 0, let handle = FileHandle(forReadingAtPath: path) else { return .unknown }
        defer { try? handle.close() }
        let newline = UInt8(ascii: "\n")
        var buffer = Data()         // byte từ `pos` tới phần đã xử lý (chưa thành dòng hoàn chỉnh)
        var pos = size
        while pos > 0, size - pos < maxScan {
            let readSize = min(chunk, pos)
            pos -= readSize
            handle.seek(toFileOffset: pos)
            buffer = handle.readData(ofLength: Int(readSize)) + buffer
            // Tách các dòng hoàn chỉnh ở cuối buffer (đứng sau một ký tự xuống dòng).
            while let nl = buffer.lastIndex(of: newline) {
                let line = buffer[buffer.index(after: nl)...]
                buffer = buffer[..<nl]
                if !line.isEmpty, let s = state(ofLine: Data(line), skipSidechain: skipSidechain) { return s }
            }
        }
        // Dòng đầu file (không có ký tự xuống dòng đứng trước).
        if pos == 0, !buffer.isEmpty, let s = state(ofLine: buffer, skipSidechain: skipSidechain) { return s }
        return .unknown
    }

    /// nil = dòng không quyết định trạng thái (hoặc không đọc được).
    static func state(ofLine line: Data, skipSidechain: Bool) -> State? {
        if let obj = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] {
            return state(ofEntry: obj, skipSidechain: skipSidechain)
        }
        // JSON.stringify của Claude Code giữ nguyên surrogate lẻ ("\ud83d", khi cắt ngắn giữa emoji),
        // JSONSerialization từ chối → thay chúng rồi thử lại.
        if let text = String(data: line, encoding: .utf8) {
            let cleaned = text.replacingOccurrences(of: #"\\u[dD][89a-fA-F][0-9a-fA-F]{2}"#, with: #"\\ufffd"#,
                                                    options: .regularExpression)
            if cleaned != text, let obj = (try? JSONSerialization.jsonObject(with: Data(cleaned.utf8))) as? [String: Any] {
                return state(ofEntry: obj, skipSidechain: skipSidechain)
            }
            return heuristicState(text, skipSidechain: skipSidechain)
        }
        return nil
    }

    /// Dự phòng cuối khi dòng vẫn không phải JSON hợp lệ: đọc vài khoá ở đầu dòng.
    private static func heuristicState(_ text: String, skipSidechain: Bool) -> State? {
        let head = text.prefix(4096)
        if skipSidechain, head.contains(#""isSidechain":true"#) { return nil }
        if head.contains(#""isMeta":true"#) { return nil }
        guard let r = head.range(of: #""type":"(user|assistant|system)""#, options: .regularExpression) else { return nil }
        switch head[r] {
        case #""type":"system""#:
            return (head.contains(#""subtype":"turn_duration""#) || head.contains(#""subtype":"local_command""#)) ? .idle : nil
        case #""type":"assistant""#:
            for stop in ["end_turn", "stop_sequence", "max_tokens", "refusal", "pause_turn"]
            where text.contains(#""stop_reason":"\#(stop)""#) { return .idle }
            return .inTurn
        default:
            if text.contains("[Request interrupted by user") || text.contains("<local-command-stdout>") { return .idle }
            return .inTurn
        }
    }

    /// nil = dòng không quyết định trạng thái (metadata, attachment…), xét tiếp dòng trước.
    static func state(ofEntry e: [String: Any], skipSidechain: Bool) -> State? {
        if skipSidechain, e["isSidechain"] as? Bool == true { return nil }
        if e["isMeta"] as? Bool == true { return nil }
        let message = e["message"] as? [String: Any]
        switch e["type"] as? String {
        case "system":
            let sub = e["subtype"] as? String
            return (sub == "turn_duration" || sub == "local_command") ? .idle : nil
        case "assistant":
            let stop = message?["stop_reason"] as? String
            return (stop == nil || stop == "tool_use") ? .inTurn : .idle
        case "user":
            let text = flatText(message?["content"])
            if text.contains("[Request interrupted by user") { return .idle }
            if text.contains("<local-command-stdout>") || text.contains("<local-command-stderr>") { return .idle }
            return .inTurn
        default:
            return nil
        }
    }

    private static func flatText(_ content: Any?) -> String {
        if let s = content as? String { return s }
        guard let parts = content as? [[String: Any]] else { return "" }
        return parts.map { part in
            if let t = part["text"] as? String { return t }
            return flatText(part["content"])
        }.joined(separator: "\n")
    }
}
