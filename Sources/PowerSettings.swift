import Foundation

/// Đọc / ghi thời gian tắt màn hình và ngủ máy (pmset).
/// Màn hình tắt cũng là lúc máy khoá nếu bật "Yêu cầu mật khẩu".
final class PowerSettings: ObservableObject {
    /// Đơn vị: phút. 0 = không bao giờ. Đổi giá trị thì xoá thông báo cũ.
    @Published var displaySleep = 10 { didSet { if !isApplying { message = nil } } }
    @Published var systemSleep = 1 { didSet { if !isApplying { message = nil } } }

    @Published private(set) var isApplying = false
    enum Message: Equatable {
        case applied, passwordCancelled
        case failed(String)
        var isError: Bool { self != .applied }
    }

    @Published private(set) var message: Message?

    private var loaded = (display: 10, system: 1)

    var hasChanges: Bool {
        (displaySleep, systemSleep) != (loaded.display, loaded.system)
    }

    init() { set(PmsetCache.refresh()) }

    /// Đọc lại từ hệ thống ở luồng nền (lúc mở menu), không làm giật giao diện.
    func reload() {
        #if DEBUG
        if previewLocked { return }
        #endif
        DispatchQueue.global(qos: .userInitiated).async {
            let v = PmsetCache.refresh()
            DispatchQueue.main.async {
                guard !self.hasChanges, !self.isApplying else { return }
                self.set(v)
            }
        }
    }

    private func set(_ v: (display: Int, sleep: Int)) {
        (displaySleep, systemSleep) = (v.display, v.sleep)
        loaded = (displaySleep, systemSleep)
    }

    #if DEBUG
    /// Chỉ dùng để chụp ảnh màn hình cho README.
    func setPreview(display: Int, sleep: Int) { set((display, sleep)); previewLocked = true }
    private var previewLocked = false
    #endif

    func clearMessage() {
        if !isApplying { message = nil }
    }

    func revert() {
        (displaySleep, systemSleep) = (loaded.display, loaded.system)
        message = nil
    }

    func apply() {
        guard !isApplying else { return }
        isApplying = true
        message = nil
        let target = (display: displaySleep, system: systemSleep)

        DispatchQueue.global(qos: .userInitiated).async {
            var error: Message?

            // pmset cần quyền admin → macOS sẽ hỏi mật khẩu một lần.
            let cmd = "/usr/bin/pmset -a displaysleep \(target.display) sleep \(target.system)"
            let script = "do shell script \"\(cmd)\" with administrator privileges"
            let r = Shell.run("/usr/bin/osascript", ["-e", script])
            if r.status != 0 {
                error = r.output.contains("-128") ? .passwordCancelled
                    : .failed(r.output.trimmingCharacters(in: .whitespacesAndNewlines))
            }

            let fresh = PmsetCache.refresh()
            DispatchQueue.main.async {
                self.isApplying = false
                if let error {
                    self.message = error
                } else {
                    self.set(fresh)
                    self.message = .applied
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        if self.message == .applied { self.message = nil }
                    }
                }
            }
        }
    }

    static func value(of key: String, in text: String) -> Int? {
        for line in text.split(separator: "\n") {
            let parts = line.split(whereSeparator: \.isWhitespace)
            if parts.count >= 2, parts[0] == key, let v = Int(parts[1]) { return v }
        }
        return nil
    }
}

/// Giá trị `pmset displaysleep` / `sleep` (phút) dùng chung, đọc lại ở luồng nền khi đã cũ hơn 60 giây.
enum PmsetCache {
    private static let lock = NSLock()
    private static var value = (display: 10, sleep: 1)
    private static var readAt = Date.distantPast
    private static var refreshing = false

    /// Đọc ngay (chạy `pmset -g`), cập nhật cache.
    @discardableResult
    static func refresh() -> (display: Int, sleep: Int) {
        let out = Shell.run("/usr/bin/pmset", ["-g"]).output
        lock.lock(); defer { lock.unlock() }
        value = (PowerSettings.value(of: "displaysleep", in: out) ?? value.display,
                 PowerSettings.value(of: "sleep", in: out) ?? value.sleep)
        readAt = Date()
        refreshing = false
        return value
    }

    /// Trả giá trị đang cache, và làm mới ở luồng nền nếu đã cũ.
    static func current() -> (display: Int, sleep: Int) {
        lock.lock(); defer { lock.unlock() }
        if Date().timeIntervalSince(readAt) > 60, !refreshing {
            refreshing = true
            DispatchQueue.global(qos: .utility).async { refresh() }
        }
        return value
    }
}

enum Shell {
    @discardableResult
    static func run(_ path: String, _ args: [String]) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (-1, error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
