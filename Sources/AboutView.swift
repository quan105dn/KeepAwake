import SwiftUI

enum AppInfo {
    static let repoURL = URL(string: "https://github.com/quan105dn/KeepAwake")!
    static let licenseURL = URL(string: "https://github.com/quan105dn/KeepAwake/blob/main/LICENSE")!
    static let authorURL = URL(string: "https://github.com/quan105dn")!
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? previewVersion.0
    }
    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? previewVersion.1
    }
    /// Dùng khi chạy ngoài app bundle (ảnh chụp màn hình, test).
    static var previewVersion = ("dev", "0")
}

/// Thông tin app: phiên bản, giấy phép, mã nguồn, quyền riêng tư.
struct AboutView: View {
    @EnvironmentObject private var l10n: L10n
    var onBack: () -> Void

    private var t: Strings { l10n.s }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Button(action: onBack) {
                    Label(t.back, systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
                Spacer()
            }

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)

            VStack(spacing: 3) {
                Text("KeepAwake").font(.title2.weight(.semibold))
                Text(t.versionLabel(AppInfo.version, AppInfo.build))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(t.tagline)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }

            VStack(spacing: 0) {
                infoRow(icon: "doc.text", title: t.license, value: "Apache License 2.0", url: AppInfo.licenseURL)
                Divider().padding(.leading, 34)
                infoRow(icon: "chevron.left.forwardslash.chevron.right", title: t.sourceCode,
                        value: "quan105dn/KeepAwake", url: AppInfo.repoURL)
                Divider().padding(.leading, 34)
                infoRow(icon: "person", title: t.author, value: "@quan105dn", url: AppInfo.authorURL)
            }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))

            Label(t.privacyNote, systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("© 2026 Quan Nguyen")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func infoRow(icon: String, title: String, value: String, url: URL) -> some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(title).font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(value).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
