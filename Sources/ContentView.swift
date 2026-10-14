import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var awake: AwakeManager
    @EnvironmentObject private var power: PowerSettings
    @EnvironmentObject private var login: LoginItem
    @EnvironmentObject private var l10n: L10n

    private var t: Strings { l10n.s }
    @StateObject private var nav = NavState()

    var body: some View {
        Group {
            if nav.showAbout {
                AboutView { nav.showAbout = false }
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    modeCard
                    settingsCard
                    footer
                }
            }
        }
        .padding(16)
        .frame(width: 340)
        .onAppear {
            login.refresh()
            power.clearMessage()
            power.reload()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(awake.isOn ? AnyShapeStyle(accent) : AnyShapeStyle(Color.secondary.opacity(0.15)))
                Image(systemName: awake.icon(off: "moon.zzz.fill"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(awake.isOn ? .white : .secondary)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 1) {
                Text("KeepAwake").font(.headline)
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    Text(statusText)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    private var statusText: String {
        if awake.mode == .claude {
            let n = awake.busySessions.count
            return n == 0 ? t.statusClaudeIdle : t.statusClaudeHolding(n)
        }
        guard awake.isOn, let since = awake.since else { return t.statusNormal }
        let minutes = Int(Date().timeIntervalSince(since) / 60)
        let duration = minutes < 1 ? t.justStarted : t.duration(minutes: minutes)
        let what = awake.mode == .full ? t.statusFull : t.statusSystemOnly
        return "\(what) · \(duration)"
    }

    private let accent = LinearGradient(colors: [Color.orange, Color.pink],
                                        startPoint: .topLeading, endPoint: .bottomTrailing)

    // MARK: - Modes

    private var modeCard: some View {
        VStack(spacing: 4) {
            modeRow(.off, icon: "moon.zzz", title: t.modeOff,
                    detail: t.modeOffDetail)
            modeRow(.claude, icon: "terminal.fill", title: t.modeClaude,
                    detail: lockMinutes.map { t.modeClaudeDetail(t.duration(minutes: $0)) } ?? t.modeClaudeNoLock)
            if awake.mode == .claude {
                claudePanel
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            modeRow(.systemOnly, icon: "lock.display", title: t.modeSystemOnly,
                    detail: power.displaySleep == 0 ? t.modeSystemOnlyNever
                        : t.modeSystemOnlyDetail(t.duration(minutes: power.displaySleep)))
            modeRow(.full, icon: "cup.and.saucer.fill", title: t.modeFull,
                    detail: t.modeFullDetail)

            Divider().padding(.vertical, 4)

            HStack {
                Text(t.resetNote)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button {
                    awake.lockScreenNow()
                } label: {
                    Label(t.lockNow, systemImage: "lock.fill")
                }
                .controlSize(.small)
                .help(t.lockNowHelp)
            }
            .padding(.horizontal, 4)
        }
        .padding(8)
        .background(card(highlighted: false))
    }

    private var claudePanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            if awake.busySessions.isEmpty {
                Label(t.noTasks, systemImage: "moon.zzz")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(awake.busySessions) { s in
                    HStack(spacing: 6) {
                        Circle().fill(Color.green).frame(width: 6, height: 6)
                        Text(s.project).font(.system(size: 12, weight: .medium))
                            .lineLimit(1).truncationMode(.middle)
                            .layoutPriority(1)
                        if let client = s.client {
                            Text(client).font(.caption2).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.tail)
                        }
                        Spacer(minLength: 4)
                        Text(sessionDetail(s)).font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).fixedSize()
                    }
                }
            }
            HStack(spacing: 6) {
                Text(t.ignoreTasksOver).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.85)
                Spacer(minLength: 4)
                Picker("", selection: $awake.maxTaskHours) {
                    ForEach([1, 2, 4, 8, 12], id: \.self) { Text(t.hours($0)).tag($0) }
                    Text(t.unlimited).tag(0)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(width: 96)
            }
            Toggle(t.forceSleep, isOn: $awake.forceSleepWhenIdle)
                .toggleStyle(.checkbox)
                .font(.caption)
                .help(t.forceSleepHelp)
            if awake.ignoredTasks > 0 {
                Text(t.ignoringTasks(awake.ignoredTasks))
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.04)))
        .padding(.horizontal, 6)
    }

    /// Màn hình khoá cùng lúc với khi tắt (nếu bật "Yêu cầu mật khẩu").
    private var lockMinutes: Int? {
        power.displaySleep > 0 ? power.displaySleep : nil
    }

    private func sessionDetail(_ s: ClaudeScanner.Session) -> String {
        if s.working { return s.taskAges.isEmpty ? t.working : t.workingWithCommands(s.taskAges.count) }
        let m = Int((s.taskAges.max() ?? 0) / 60)
        let age = m < 1 ? t.justRan : m < 60 ? t.minutes(m) : t.shortHoursMinutes(m / 60, m % 60)
        return t.backgroundTasks(s.taskAges.count, age)
    }

    private func modeRow(_ mode: AwakeManager.Mode, icon: String, title: String, detail: String) -> some View {
        let selected = awake.mode == mode
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { awake.set(mode) }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(selected ? AnyShapeStyle(accent) : AnyShapeStyle(Color.primary.opacity(0.07)))
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selected ? .white : .secondary)
                }
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13, weight: selected ? .semibold : .regular))
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(accent)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Color.orange.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Normal-mode settings

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(t.systemSettings)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            row(t.displayOffAfter, icon: "display", selection: $power.displaySleep,
                overridden: awake.mode == .full, options: [1, 2, 5, 10, 15, 20, 30, 60, 120, 180, 0])
            row(t.sleepAfter, icon: "powersleep", selection: $power.systemSleep,
                overridden: awake.isHolding, options: [1, 5, 10, 15, 30, 60, 120, 180, 0])

            HStack(spacing: 8) {
                if let msg = power.message {
                    Text(messageText(msg))
                        .font(.caption)
                        .foregroundStyle(msg.isError ? Color.red : Color.green)
                        .lineLimit(2)
                } else {
                    Button(t.lockPassword) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Lock-Screen-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
                Spacer()
                if power.hasChanges {
                    Button(t.cancel) { power.revert() }
                        .controlSize(.small)
                }
                // Nền cam chỉ khi bấm được; lúc vô hiệu dùng nút xám chuẩn cho dễ đọc.
                applyButton
            }
            .padding(.top, 2)
        }
        .padding(12)
        .background(card(highlighted: false))
    }

    private var applyButton: some View {
        let enabled = power.hasChanges && !power.isApplying
        return Button {
            power.apply()
        } label: {
            if power.isApplying {
                ProgressView().controlSize(.mini).frame(width: 56)
            } else {
                Text(t.apply).frame(width: 56)
            }
        }
        .buttonStyle(PillButtonStyle(prominent: enabled))
        .disabled(!enabled)
    }

    private func row(_ title: String, icon: String, selection: Binding<Int>, overridden: Bool, options: [Int]) -> some View {
        // Giữ được cả giá trị hiện tại nếu nó không nằm trong danh sách sẵn có.
        let all = options.contains(selection.wrappedValue) ? options : (options + [selection.wrappedValue])
        let sorted = all.filter { $0 > 0 }.sorted() + (all.contains(0) ? [0] : [])
        return HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(title).font(.system(size: 13))
                .lineLimit(1).minimumScaleFactor(0.85)
                .layoutPriority(1)
                .foregroundStyle(overridden ? .secondary : .primary)
            Spacer(minLength: 4)
            if overridden {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .help(t.overriddenHelp)
            }
            Picker("", selection: selection) {
                ForEach(sorted, id: \.self) { Text(t.duration(minutes: $0)).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 104)
            .disabled(power.isApplying)
        }
    }

    private func messageText(_ m: PowerSettings.Message) -> String {
        switch m {
        case .applied: return t.applied
        case .passwordCancelled: return t.passwordCancelled
        case .failed(let detail): return t.applyFailed(detail)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle(t.launchAtLogin,
                       isOn: Binding(get: { login.isEnabled }, set: { login.set($0) }))
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
                Spacer()
                Menu {
                    Picker(t.language, selection: $l10n.language) {
                        ForEach(Language.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(l10n.language.rawValue.uppercased(), systemImage: "globe")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(t.language)
                Button {
                    nav.showAbout = true
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.borderless)
                .help(t.about)
                Button(t.quit) { NSApp.terminate(nil) }
                    .controlSize(.small)
                    .keyboardShortcut("q")
            }
            if let err = login.error {
                Text(t.loginError(err)).font(.caption2).foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 2)
    }

    private func card(highlighted: Bool) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(highlighted ? Color.orange.opacity(0.12) : Color.primary.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(highlighted ? Color.orange.opacity(0.35) : Color.primary.opacity(0.06))
            )
    }
}

/// Nút tự vẽ: màu cố định nên không bị hệ thống pha nhạt (Liquid Glass / vibrancy).
struct PillButtonStyle: ButtonStyle {
    var prominent: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: prominent ? .semibold : .regular))
            .foregroundStyle(prominent ? Color.white : Color.primary.opacity(isEnabled ? 0.85 : 0.5))
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(prominent
                          ? AnyShapeStyle(LinearGradient(colors: [Color(red: 0.95, green: 0.45, blue: 0.1),
                                                                  Color(red: 0.9, green: 0.25, blue: 0.35)],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                          : AnyShapeStyle(Color.primary.opacity(0.1)))
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// Màn hình đang hiện trong menu. Dùng ObservableObject thay cho @State vì macro @State
/// cần plugin chỉ có trong Xcode, không có trong Command Line Tools.
final class NavState: ObservableObject {
    @Published var showAbout = false
}
