import Foundation

/// Nhật ký chẩn đoán gọn: ~/Library/Logs/KeepAwake.log (tự cắt khi quá 1 MB).
enum Log {
    /// `KEEPAWAKE_LOG` đổi đường dẫn (dùng khi chạy test để không ghi vào log thật).
    static let url = ProcessInfo.processInfo.environment["KEEPAWAKE_LOG"].map { URL(fileURLWithPath: $0) }
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/KeepAwake.log")
    private static let queue = DispatchQueue(label: "KeepAwake.log")
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    static func write(_ message: String) {
        let line = "\(formatter.string(from: Date()))  \(message)\n"
        queue.async {
            let fm = FileManager.default
            if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 1_000_000 {
                try? fm.removeItem(at: url)
            }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: url)
            }
        }
    }
}
