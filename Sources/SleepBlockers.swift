import Foundation
import IOKit.pwr_mgt

/// Đọc các power assertion đang bật trên hệ thống để quyết định có nên ép ngủ hay không.
enum SleepBlockers {
    struct Blocker: CustomStringConvertible {
        let pid: pid_t
        let name: String
        let type: String
        var description: String { "\(name)(\(pid)) \(type)" }
    }

    static func all() -> [Blocker] {
        var dict: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&dict) == kIOReturnSuccess,
              let byPid = dict?.takeRetainedValue() as? [NSNumber: [[String: Any]]]
        else { return [] }
        var result: [Blocker] = []
        for (pidNumber, assertions) in byPid {
            let pid = pid_t(pidNumber.int32Value)
            let name = ClaudeScanner.info(of: pid)?.name ?? "?"
            for a in assertions {
                guard let type = a["AssertType"] as? String,
                      (a["AssertLevel"] as? Int ?? 0) > 0 else { continue }
                result.append(Blocker(pid: pid, name: name, type: type))
            }
        }
        return result
    }

    private static let systemSleepTypes: Set<String> = [
        "PreventUserIdleSystemSleep", "PreventSystemSleep", "NoIdleSleepAssertion",
    ]
    private static let displaySleepTypes: Set<String> = [
        "PreventUserIdleDisplaySleep", "NoDisplaySleepAssertion",
    ]

    /// Chặn ngủ có chủ đích → không ép ngủ: `caffeinate` do người dùng chạy
    /// (không phải của Claude Code) và Time Machine.
    /// Chặn ngủ vô ý (vd. emulator giữ âm thanh qua coreaudiod) không nằm trong danh sách này.
    static func respected(in blockers: [Blocker]) -> [Blocker] {
        blockers.filter { b in
            guard systemSleepTypes.contains(b.type) else { return false }
            if b.name == "caffeinate" {
                guard let parent = ClaudeScanner.info(of: b.pid)?.ppid else { return true }
                return !ClaudeScanner.isClaudeCode(pid: parent)
            }
            return b.name.hasPrefix("backupd")
        }
    }

    /// App khác đang giữ màn hình sáng (trình phát video, slide…), trừ chính KeepAwake.
    static func displayHolders(in blockers: [Blocker]) -> [Blocker] {
        blockers.filter { displaySleepTypes.contains($0.type) && $0.pid != getpid() }
    }
}
