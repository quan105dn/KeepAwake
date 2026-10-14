import SwiftUI

@main
enum Launcher {
    static func main() {
        if CommandLine.arguments.contains("--diagnose") {
            Diagnose.run()
            return
        }
        KeepAwakeApp.main()
    }
}

/// `/Applications/KeepAwake.app/Contents/MacOS/KeepAwake --diagnose`: in ra cách app nhìn thấy từng phiên
/// Claude Code (chỉ đọc, không đổi gì), để gửi kèm khi báo lỗi.
enum Diagnose {
    static func run() {
        let info = Bundle.main.infoDictionary
        print("KeepAwake \(info?["CFBundleShortVersionString"] ?? "dev") (\(info?["CFBundleVersion"] ?? "0")), macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        let hours = UserDefaults.standard.object(forKey: "maxTaskHours") as? Int ?? 4
        print("Ignore background tasks after: " + (hours > 0 ? "\(hours) h" : "no limit"))
        let result = ClaudeScanner.diagnose(maxTaskAge: hours > 0 ? TimeInterval(hours * 3600) : nil)
        if result.sessions.isEmpty { print("\nNo Claude Code sessions found.") }
        for s in result.sessions {
            print("\n== pid \(s.id)  \(s.project)  [\(s.client ?? "?")]  →  \(s.isBusy ? "BUSY" : "idle") (working=\(s.working), tasks=\(s.taskAges.count))")
            s.debug.forEach { print("   " + $0) }
        }
        if !result.skipped.isEmpty {
            print("\nSkipped processes:")
            result.skipped.forEach { print("   " + $0) }
        }
        print("\nSleep blockers: " + SleepBlockers.all().map(\.description).joined(separator: ", "))
    }
}

struct KeepAwakeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var awake = AwakeManager.shared
    @StateObject private var power = PowerSettings()
    @StateObject private var login = LoginItem()
    @StateObject private var l10n = L10n()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(awake)
                .environmentObject(power)
                .environmentObject(login)
                .environmentObject(l10n)
        } label: {
            Image(systemName: awake.icon(off: "cup.and.saucer"))
        }
        .menuBarExtraStyle(.window)
    }

}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Chặn App Nap (nhưng vẫn cho máy ngủ) để bộ quét 10 giây chạy cả khi máy đang DarkWake.
    private var activity: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "KeepAwake monitors Claude Code and sleep state")
        Log.write("launched")

        let center = NSWorkspace.shared.notificationCenter
        for (name, text) in [(NSWorkspace.willSleepNotification, "system will sleep"),
                             (NSWorkspace.didWakeNotification, "system did wake"),
                             (NSWorkspace.screensDidSleepNotification, "screens did sleep"),
                             (NSWorkspace.screensDidWakeNotification, "screens did wake")] {
            center.addObserver(forName: name, object: nil, queue: .main) { _ in Log.write(text) }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        AwakeManager.shared.disable()
    }
}
