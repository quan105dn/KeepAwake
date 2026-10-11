import Foundation
import Darwin

/// Quét cây tiến trình để biết Claude Code có đang làm việc / chạy tác vụ không.
/// - Con `caffeinate` của `claude`: Claude Code đang xử lý một lượt.
/// - Con shell có args chứa `.claude/shell-snapshots`: lệnh Bash Claude chạy (kể cả chạy nền).
enum ClaudeScanner {
    struct Session: Identifiable, Equatable {
        let id: pid_t
        let project: String
        var working = false
        /// Tuổi (giây) của các tác vụ shell đang chạy, đã lọc theo giới hạn.
        var taskAges: [TimeInterval] = []
        var ignoredTasks = 0
        var isBusy: Bool { working || !taskAges.isEmpty }
    }

    private struct Proc {
        let pid: pid_t
        let ppid: pid_t
        let name: String
        let start: Date
    }

    /// - Parameter maxTaskAge: bỏ qua tác vụ chạy lâu hơn mức này (nil = không giới hạn).
    static func scan(maxTaskAge: TimeInterval?) -> [Session] {
        let procs = allProcesses()
        let now = Date()
        var sessions: [Session] = []
        for claude in procs where isClaudeCode(claude) {
            var s = Session(id: claude.pid, project: cwd(of: claude.pid).map { ($0 as NSString).lastPathComponent } ?? "Claude Code")
            for child in procs where child.ppid == claude.pid {
                switch child.name {
                case "caffeinate":
                    s.working = true
                case "zsh", "bash", "sh", "fish":
                    guard arguments(of: child.pid).contains(".claude/shell-snapshots") else { continue }
                    let age = now.timeIntervalSince(child.start)
                    if let max = maxTaskAge, age > max { s.ignoredTasks += 1 } else { s.taskAges.append(age) }
                default:
                    continue
                }
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

    /// Bản native: tiến trình `claude` / `claude.exe`.
    /// Bản cài qua npm: `node …/bin/claude` hoặc `node …/@anthropic-ai/claude-code/cli.js`.
    private static func isClaudeCode(_ p: Proc) -> Bool {
        if p.name == "claude" || p.name == "claude.exe" { return true }
        guard p.name == "node" else { return false }
        let args = argv(of: p.pid)
        guard args.count >= 2 else { return false }
        return (args[1] as NSString).lastPathComponent == "claude"
            || args[1].contains("@anthropic-ai/claude-code/")
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

    /// Đọc argv qua KERN_PROCARGS2: [argc][exec path]\0…\0[argv0]\0[argv1]\0…
    private static func argv(of pid: pid_t) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }
        var buf = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0 else { return [] }
        let argc = Int(buf.withUnsafeBytes { $0.load(as: Int32.self) })
        var i = MemoryLayout<Int32>.size
        while i < size, buf[i] != 0 { i += 1 }   // bỏ qua exec path
        while i < size, buf[i] == 0 { i += 1 }   // và phần đệm
        var result: [String] = []
        while i < size, result.count < argc {
            let start = i
            while i < size, buf[i] != 0 { i += 1 }
            result.append(String(decoding: buf[start..<i], as: UTF8.self))
            i += 1
        }
        return result
    }

    private static func cwd(of pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        var path = info.pvi_cdir.vip_path
        return withUnsafeBytes(of: &path) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }
}
