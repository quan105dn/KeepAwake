import SwiftUI

@main
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
