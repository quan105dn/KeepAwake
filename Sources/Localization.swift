import Foundation

enum Language: String, CaseIterable, Identifiable {
    case en, vi
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .en: return "English"
        case .vi: return "Tiếng Việt"
        }
    }
}

/// Ngôn ngữ giao diện, lưu trong UserDefaults nên giữ nguyên sau khi thoát app / khởi động lại.
final class L10n: ObservableObject {
    @Published var language: Language {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "language") }
    }

    var s: Strings { language == .vi ? .vi : .en }

    init() {
        let saved = UserDefaults.standard.string(forKey: "language")
        language = saved.flatMap(Language.init(rawValue:)) ?? .en
    }
}

/// Toàn bộ chuỗi hiển thị. Thêm ngôn ngữ mới = thêm một `static let` và một case trong `Language`.
struct Strings {
    // Header
    let statusNormal: String
    let statusClaudeIdle: String
    let statusClaudeHolding: (Int) -> String
    let statusFull: String
    let statusSystemOnly: String
    let justStarted: String

    // Modes
    let modeOff: String
    let modeOffDetail: String
    let modeClaude: String
    let modeClaudeDetail: (String) -> String
    let modeClaudeNoLock: String
    let modeSystemOnly: String
    let modeSystemOnlyNever: String
    let modeSystemOnlyDetail: (String) -> String
    let modeFull: String
    let modeFullDetail: String
    let resetNote: String
    let lockNow: String
    let lockNowHelp: String

    // Claude panel
    let noTasks: String
    let ignoreTasksOver: String
    let ignoringTasks: (Int) -> String
    let forceSleep: String
    let forceSleepHelp: String
    let working: String
    let workingWithCommands: (Int) -> String
    let backgroundTasks: (Int, String) -> String
    let justRan: String

    // System settings
    let systemSettings: String
    let displayOffAfter: String
    let sleepAfter: String
    let lockPassword: String
    let cancel: String
    let apply: String
    let overriddenHelp: String
    let applied: String
    let passwordCancelled: String
    let applyFailed: (String) -> String

    // Durations
    let never: String
    let unlimited: String
    let minutes: (Int) -> String
    let hours: (Int) -> String
    let hoursMinutes: (Int, Int) -> String
    let shortHoursMinutes: (Int, Int) -> String

    // Footer
    let launchAtLogin: String
    let loginError: (String) -> String
    let quit: String
    let language: String

    // About
    let about: String
    let back: String
    let versionLabel: (String, String) -> String
    let tagline: String
    let license: String
    let sourceCode: String
    let author: String
    let privacyNote: String

    func duration(minutes m: Int) -> String {
        switch m {
        case 0: return never
        case ..<60: return minutes(m)
        case let m where m % 60 == 0: return hours(m / 60)
        default: return hoursMinutes(m / 60, m % 60)
        }
    }

    static let en = Strings(
        statusNormal: "Using normal settings",
        statusClaudeIdle: "Claude Code · idle, sleeps normally",
        statusClaudeHolding: { "Claude Code · keeping awake (\($0) session\($0 == 1 ? "" : "s"))" },
        statusFull: "Keeping the Mac awake",
        statusSystemOnly: "Running, display turns off",
        justStarted: "just started",

        modeOff: "Normal",
        modeOffDetail: "Sleep & lock follow the settings below",
        modeClaude: "Follow Claude Code",
        modeClaudeDetail: { "Awake for Claude · locks after \($0)" },
        modeClaudeNoLock: "Awake for Claude · no auto-lock",
        modeSystemOnly: "Running, display off",
        modeSystemOnlyNever: "No sleep · display never turns off",
        modeSystemOnlyDetail: { "No sleep · off & locks after \($0)" },
        modeFull: "Always awake",
        modeFullDetail: "No sleep, no display off, no lock",
        resetNote: "Resets when the app quits or the Mac restarts",
        lockNow: "Lock now",
        lockNowHelp: "Lock and turn off the display now; the Mac keeps running unless in Normal mode",

        noTasks: "Nothing is running",
        ignoreTasksOver: "Ignore background tasks after",
        ignoringTasks: { "Ignoring \($0) long-running task\($0 == 1 ? "" : "s")" },
        forceSleep: "Force sleep when done & display is off",
        forceSleepHelp: "When no Claude Code work has run for 2 minutes and the display is off, put the Mac to sleep even if other apps (e.g. an emulator holding audio) are preventing it",
        working: "working",
        workingWithCommands: { "working · \($0) cmd\($0 == 1 ? "" : "s")" },
        backgroundTasks: { "\($0) background task\($0 == 1 ? "" : "s") · \($1)" },
        justRan: "just started",

        systemSettings: "System settings",
        displayOffAfter: "Display off & lock after",
        sleepAfter: "Sleep after",
        lockPassword: "Lock screen password…",
        cancel: "Cancel",
        apply: "Apply",
        overriddenHelp: "Temporarily ignored because of the active mode",
        applied: "Applied ✓",
        passwordCancelled: "Password prompt cancelled.",
        applyFailed: { "Couldn't apply: \($0)" },

        never: "Never",
        unlimited: "Unlimited",
        minutes: { "\($0) min" },
        hours: { "\($0) hr" },
        hoursMinutes: { "\($0) hr \($1) min" },
        shortHoursMinutes: { "\($0)h\($1)m" },

        launchAtLogin: "Launch at login",
        loginError: { "Couldn't change: \($0)" },
        quit: "Quit",
        language: "Language",

        about: "About KeepAwake",
        back: "Back",
        versionLabel: { "Version \($0) (\($1))" },
        tagline: "Keep your Mac awake only when it matters.",
        license: "License",
        sourceCode: "Source code",
        author: "Author",
        privacyNote: "No network access, no analytics, no tracking. Everything stays on your Mac."
    )

    static let vi = Strings(
        statusNormal: "Đang dùng cài đặt bình thường",
        statusClaudeIdle: "Theo Claude Code · đang rảnh, máy ngủ bình thường",
        statusClaudeHolding: { "Theo Claude Code · đang giữ máy thức (\($0) phiên)" },
        statusFull: "Đang giữ máy thức",
        statusSystemOnly: "Máy chạy, màn hình tự tắt",
        justStarted: "vừa bật",

        modeOff: "Bình thường",
        modeOffDetail: "Ngủ & khoá theo cài đặt bên dưới",
        modeClaude: "Theo Claude Code",
        modeClaudeDetail: { "Thức khi Claude chạy · khoá sau \($0)" },
        modeClaudeNoLock: "Thức khi Claude chạy · không tự khoá",
        modeSystemOnly: "Máy chạy, màn hình tắt",
        modeSystemOnlyNever: "Không ngủ · màn hình không tự tắt",
        modeSystemOnlyDetail: { "Không ngủ · tắt & khoá sau \($0)" },
        modeFull: "Luôn thức",
        modeFullDetail: "Không ngủ, không tắt, không khoá màn hình",
        resetNote: "Hết hiệu lực khi thoát app/khởi động lại",
        lockNow: "Khoá ngay",
        lockNowHelp: "Khoá và tắt màn hình ngay, máy vẫn chạy nếu không ở chế độ Bình thường",

        noTasks: "Không có việc nào đang chạy",
        ignoreTasksOver: "Bỏ qua tác vụ nền chạy quá",
        ignoringTasks: { "Đang bỏ qua \($0) tác vụ chạy quá lâu" },
        forceSleep: "Ép ngủ khi xong việc & màn hình đã tắt",
        forceSleepHelp: "Khi Claude Code hết việc 2 phút và màn hình đã tắt, cho máy ngủ luôn kể cả khi app khác đang chặn (vd. emulator giữ âm thanh)",
        working: "đang làm việc",
        workingWithCommands: { "làm việc · \($0) lệnh" },
        backgroundTasks: { "\($0) tác vụ nền · \($1)" },
        justRan: "vừa chạy",

        systemSettings: "Cài đặt hệ thống",
        displayOffAfter: "Tắt & khoá màn hình sau",
        sleepAfter: "Máy ngủ sau",
        lockPassword: "Mật khẩu khi khoá…",
        cancel: "Huỷ",
        apply: "Áp dụng",
        overriddenHelp: "Đang tạm bỏ qua do chế độ đang bật",
        applied: "Đã áp dụng ✓",
        passwordCancelled: "Đã huỷ nhập mật khẩu.",
        applyFailed: { "Không áp dụng được: \($0)" },

        never: "Không bao giờ",
        unlimited: "Không giới hạn",
        minutes: { "\($0) phút" },
        hours: { "\($0) giờ" },
        hoursMinutes: { "\($0) giờ \($1) phút" },
        shortHoursMinutes: { "\($0)g\($1)p" },

        launchAtLogin: "Khởi động cùng macOS",
        loginError: { "Không đổi được: \($0)" },
        quit: "Thoát",
        language: "Ngôn ngữ",

        about: "Giới thiệu KeepAwake",
        back: "Quay lại",
        versionLabel: { "Phiên bản \($0) (\($1))" },
        tagline: "Giữ máy thức chỉ khi thật sự cần.",
        license: "Giấy phép",
        sourceCode: "Mã nguồn",
        author: "Tác giả",
        privacyNote: "Không kết nối mạng, không thu thập hay gửi dữ liệu. Mọi thứ chỉ nằm trên máy bạn."
    )
}
