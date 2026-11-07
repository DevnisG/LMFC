import AppKit
import SwiftUI

struct CleaningPermissionView: View {
    let permission: CleaningPermission

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(permission.title, systemImage: "lock.shield")
                .font(.subheadline.weight(.semibold))

            Text(permission.instructions)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if permission == .inputMonitoring {
                Text("If macOS asks you to quit and reopen LMFC, follow that prompt.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                } label: {
                    Label("Show LMFC in Finder", systemImage: "folder")
                        .frame(minHeight: InterfaceStyle.controlHeight)
                }
                .modifier(GlassSecondaryButton())

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(Bundle.main.bundleURL.path, forType: .string)
                } label: {
                    Label("Copy App Path", systemImage: "document.on.document")
                        .frame(minHeight: InterfaceStyle.controlHeight)
                }
                .modifier(GlassSecondaryButton())
                .help("Paste this path with Command–Shift–G in the Add App dialog")
            }
            .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 13))
    }
}

extension CleaningPermission {
    var title: LocalizedStringKey {
        switch self {
        case .accessibility: "Allow Accessibility"
        case .inputMonitoring: "Allow Input Monitoring"
        }
    }

    var instructions: LocalizedStringKey {
        switch self {
        case .accessibility:
            "In Privacy & Security → Accessibility, turn on LMFC. If it’s missing, click + and choose this copy."
        case .inputMonitoring:
            "In Privacy & Security → Input Monitoring, turn on LMFC. If it’s missing, click + and choose this copy."
        }
    }

    func openSettings() {
        let anchor: String
        switch self {
        case .accessibility: anchor = "Privacy_Accessibility"
        case .inputMonitoring: anchor = "Privacy_ListenEvent"
        }
        if let pane = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(anchor)"),
           NSWorkspace.shared.open(pane) {
            return
        }
        if let settings = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") {
            NSWorkspace.shared.openApplication(at: settings, configuration: .init())
        }
    }
}
