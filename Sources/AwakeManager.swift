import Foundation
import IOKit.pwr_mgt
import CoreGraphics
import AppKit

/// Giữ máy thức bằng IOKit power assertions (giống `caffeinate`).
/// Assertion gắn với tiến trình: thoát app hoặc khởi động lại máy là tự hết hiệu lực,
/// không thay đổi bất kỳ cài đặt hệ thống nào.
final class AwakeManager: ObservableObject {
    enum Mode: Equatable {
        /// Theo cài đặt hệ thống.
        case off
        /// Máy không ngủ, nhưng màn hình vẫn tắt / khoá theo hẹn giờ (giống `caffeinate -i`).
        case systemOnly
        /// Không ngủ, không tắt & không khoá màn hình (giống `caffeinate -dims`).
        case full
        /// Chỉ không ngủ khi Claude Code đang làm việc / chạy tác vụ; màn hình vẫn tắt & khoá.
        case claude
    }

    static let shared = AwakeManager()

    /// Biểu tượng SF Symbol của chế độ hiện tại (dùng cho thanh menu và tiêu đề).
    func icon(off: String) -> String {
        switch mode {
        case .off: return off
        case .systemOnly: return "lock.display"
        case .full: return "cup.and.saucer.fill"
        case .claude: return isHolding ? "terminal.fill" : "terminal"
        }
    }

    @Published private(set) var mode = Mode.off
    @Published private(set) var since: Date?

    /// Các phiên Claude Code đang bận (chỉ cập nhật ở chế độ `.claude`).
    @Published private(set) var busySessions: [ClaudeScanner.Session] = []
    @Published private(set) var ignoredTasks = 0

    /// Bỏ qua tác vụ chạy lâu hơn số giờ này (0 = không giới hạn), phòng dev server chạy nền mãi.
    @Published var maxTaskHours: Int = UserDefaults.standard.object(forKey: "maxTaskHours") as? Int ?? 4 {
        didSet {
            UserDefaults.standard.set(maxTaskHours, forKey: "maxTaskHours")
            if mode == .claude { scanClaude() }
        }
    }

    /// Hết việc + màn hình đã tắt thì ép máy ngủ (vượt qua app khác đang chặn ngủ, vd. emulator giữ audio).
    @Published var forceSleepWhenIdle: Bool = UserDefaults.standard.object(forKey: "forceSleepWhenIdle") as? Bool ?? true {
        didSet { UserDefaults.standard.set(forceSleepWhenIdle, forKey: "forceSleepWhenIdle") }
    }

    /// Phải rảnh liên tục ngần này mới ép ngủ, tránh khoảng nghỉ ngắn giữa các bước của Claude.
    static let idleGrace: TimeInterval = 120
    /// Có thể thay khi test để không ngủ máy thật.
    var sleepAction: () -> Void = {
        DispatchQueue.global(qos: .userInitiated).async {
            let r = Shell.run("/usr/bin/pmset", ["sleepnow"])
            Log.write("pmset sleepnow → exit \(r.status) \(r.output.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }
    /// Người dùng đã rời máy: màn hình chính đã tắt, hoặc không có thao tác chuột/phím lâu hơn
    /// thời gian tắt màn hình (dự phòng khi CGDisplayIsAsleep báo sai, vd. lúc DarkWake).
    /// Cách dự phòng chỉ dùng khi không app nào đang giữ màn hình sáng (vd. đang xem video).
    var isUserAway: () -> (away: Bool, detail: String) = {
        let displayAsleep = CGDisplayIsAsleep(CGMainDisplayID()) != 0
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState,
                                                           eventType: CGEventType(rawValue: ~0)!)
        let threshold = TimeInterval(PmsetCache.current().display * 60)
        let holders = SleepBlockers.displayHolders(in: SleepBlockers.all())
        let away = displayAsleep || (threshold > 0 && idle >= threshold && holders.isEmpty)
        return (away, "displayAsleep=\(displayAsleep) userIdle=\(Int(idle))s threshold=\(Int(threshold))s"
                      + (holders.isEmpty ? "" : " displayHeldBy=\(holders.map(\.name))"))
    }
    /// Lý do KHÔNG ép ngủ (nil = được ép): người dùng đặt "Máy ngủ sau: Không bao giờ",
    /// hoặc có lệnh chặn ngủ có chủ đích (caffeinate của người dùng, Time Machine).
    var sleepVeto: () -> String? = {
        if PmsetCache.current().sleep == 0 { return "system sleep is set to Never" }
        let respected = SleepBlockers.respected(in: SleepBlockers.all())
        return respected.isEmpty ? nil : "respecting \(respected)"
    }

    var isOn: Bool { mode != .off }
    /// Máy đang thực sự bị giữ không ngủ.
    var isHolding: Bool { mode == .systemOnly || mode == .full || (mode == .claude && !busySessions.isEmpty) }

    private let reason = "KeepAwake: keeping the Mac awake" as CFString
    private var displayAssertion: IOPMAssertionID = 0
    private var systemAssertion: IOPMAssertionID = 0
    private var activityAssertion: IOPMAssertionID = 0
    private var activityTimer: Timer?
    private var scanTimer: Timer?
    private let scanQueue = DispatchQueue(label: "KeepAwake.scan", qos: .utility)
    private var scanInFlight = false
    private var lastBusy = Date()
    private var lastForcedSleep = Date.distantPast
    private var wasBusy = false
    private var loggedWaiting = false
    /// Sau "Khoá ngay" ở chế độ Luôn thức: tạm ngừng báo hoạt động để màn hình được tắt.
    private var activityPaused = false

    private init() {
        let resume: (Notification) -> Void = { [weak self] _ in
            guard let self, self.activityPaused else { return }
            self.activityPaused = false
            if self.mode == .full { self.declareActivity() }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main, using: resume)
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main, using: resume)
    }

    func set(_ newMode: Mode) {
        guard newMode != mode else { return }
        releaseAll()
        let level = IOPMAssertionLevel(kIOPMAssertionLevelOn)

        switch newMode {
        case .off:
            break
        case .systemOnly:
            IOPMAssertionCreateWithName("PreventUserIdleSystemSleep" as CFString, level, reason, &systemAssertion)
        case .full:
            IOPMAssertionCreateWithName("PreventUserIdleDisplaySleep" as CFString, level, reason, &displayAssertion)
            IOPMAssertionCreateWithName("PreventUserIdleSystemSleep" as CFString, level, reason, &systemAssertion)
            // Báo "người dùng đang hoạt động" định kỳ để reset bộ đếm idle,
            // nhờ vậy screensaver không chạy và màn hình không tự khoá.
            declareActivity()
            let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.declareActivity() }
            RunLoop.main.add(timer, forMode: .common)
            activityTimer = timer
        case .claude:
            mode = newMode
            lastBusy = Date()
            scanClaude()
            let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in self?.scanClaude() }
            RunLoop.main.add(timer, forMode: .common)
            scanTimer = timer
        }

        Log.write("mode: \(newMode)")
        // Đổi qua lại giữa 2 chế độ bật thì giữ nguyên mốc thời gian.
        if newMode == .off { since = nil } else if since == nil { since = Date() }
        mode = newMode
    }

    func disable() { set(.off) }

    #if DEBUG
    /// Chỉ dùng để chụp ảnh màn hình cho README (không có trong bản release).
    func setPreview(mode: Mode, sessions: [ClaudeScanner.Session]) {
        self.mode = mode
        busySessions = sessions
        since = Date().addingTimeInterval(-47 * 60)
    }
    #endif

    /// Khoá màn hình rồi tắt màn hình ngay; máy vẫn tiếp tục chạy nếu đang ở chế độ bật.
    func lockScreenNow() {
        if mode == .full { activityPaused = true }
        if let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY),
           let sym = dlsym(handle, "SACLockScreenImmediate") {
            typealias LockFn = @convention(c) () -> Int32
            _ = unsafeBitCast(sym, to: LockFn.self)()
        }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.6) {
            Shell.run("/usr/bin/pmset", ["displaysleepnow"])
        }
    }

    /// Quét ở luồng nền (đọc transcript có thể mất vài chục ms), cập nhật trạng thái ở luồng chính.
    private func scanClaude() {
        guard mode == .claude, !scanInFlight else { return }
        scanInFlight = true
        let maxAge = maxTaskHours > 0 ? TimeInterval(maxTaskHours * 3600) : nil
        scanQueue.async {
            let sessions = ClaudeScanner.scan(maxTaskAge: maxAge)
            DispatchQueue.main.async {
                self.scanInFlight = false
                guard self.mode == .claude else { return }
                self.busySessions = sessions.filter(\.isBusy)
                self.ignoredTasks = sessions.reduce(0) { $0 + $1.ignoredTasks }
                self.update(busy: !self.busySessions.isEmpty, now: Date())
            }
        }
    }

    /// Giữ / nhả assertion và ép ngủ khi cần. Tách riêng để test được.
    func update(busy: Bool, now: Date) {
        if busy, systemAssertion == 0 {
            IOPMAssertionCreateWithName("PreventUserIdleSystemSleep" as CFString,
                                        IOPMAssertionLevel(kIOPMAssertionLevelOn), reason, &systemAssertion)
        } else if !busy, systemAssertion != 0 {
            IOPMAssertionRelease(systemAssertion)
            systemAssertion = 0
        }

        if busy != wasBusy {
            Log.write(busy ? "busy: " + busySessions.map(\.project).joined(separator: ", ")
                           : "idle: no Claude Code work")
            wasBusy = busy
            loggedWaiting = false
        }

        if busy {
            lastBusy = now
            return
        }
        guard forceSleepWhenIdle,
              now.timeIntervalSince(lastBusy) >= Self.idleGrace,
              now.timeIntervalSince(lastForcedSleep) >= 300 else { return }

        let user = isUserAway()
        let veto = user.away ? sleepVeto() : nil
        if user.away, let veto {
            if !loggedWaiting {
                Log.write("idle, not forcing sleep: \(veto)")
                loggedWaiting = true
            }
        } else if user.away {
            Log.write("force sleep (\(user.detail))")
            lastForcedSleep = now
            loggedWaiting = false
            sleepAction()
        } else if !loggedWaiting {
            Log.write("idle, waiting for user to leave (\(user.detail))")
            loggedWaiting = true
        }
    }

    private func releaseAll() {
        activityTimer?.invalidate()
        activityTimer = nil
        scanTimer?.invalidate()
        scanTimer = nil
        busySessions = []
        ignoredTasks = 0
        wasBusy = false
        loggedWaiting = false
        activityPaused = false
        for id in [displayAssertion, systemAssertion, activityAssertion] where id != 0 {
            IOPMAssertionRelease(id)
        }
        displayAssertion = 0
        systemAssertion = 0
        activityAssertion = 0
    }

    private func declareActivity() {
        guard !activityPaused else { return }
        IOPMAssertionDeclareUserActivity(reason, kIOPMUserActiveLocal, &activityAssertion)
    }
}
