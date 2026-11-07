import AppKit
import SwiftUI

struct CleaningView: View {
    private static let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String

    let session: CleaningSession
    @Binding var language: InterfaceLanguage
    @State private var duration: Int? = 90
    @State private var requiredPermission: CleaningPermission?
    @State private var blockTrackpad = true
    @State private var blackOutScreen = true
    @State private var confirmCleaning = false
    @State private var screenBlackout = ScreenBlackout()
    @State private var contentHeight: CGFloat = 520
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    cleaningPanel
                    if !session.isActive {
                        CleaningGuideView()
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(contentHeight, max(280, (NSScreen.main?.visibleFrame.height ?? 820) - 200)))
            footer
        }
        .padding(.horizontal, 24)
        .padding(.top, 32)
        .padding(.bottom, 18)
        .frame(width: 472)
        .background {
            windowColor
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .onAppear(perform: refresh)
        .onDisappear {
            session.interrupt()
            screenBlackout.hide()
        }
        .onChange(of: session.isScreenBlackoutActive) { _, isActive in
            if isActive {
                if !screenBlackout.show(session: session, locale: language.locale) {
                    session.interrupt()
                }
            } else {
                screenBlackout.hide()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            if session.isScreenBlackoutActive { session.interrupt() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            if session.isScreenBlackoutActive { session.interrupt() }
        }
        .onReceive(workspaceNotification(NSWorkspace.willSleepNotification)) { _ in
            session.interrupt()
        }
        .onReceive(workspaceNotification(NSWorkspace.sessionDidResignActiveNotification)) { _ in
            session.interrupt()
        }
        .onReceive(workspaceNotification(NSWorkspace.screensDidSleepNotification)) { _ in
            session.interrupt()
        }
        .alert(confirmationTitle, isPresented: $confirmCleaning) {
            Button("Cancel", role: .cancel) {}
            Button("Start Cleaning") {
                session.start(seconds: duration, blockPointer: blockTrackpad, blackoutScreen: blackOutScreen)
                refresh()
            }
        } message: {
            Text(confirmationMessage)
        }
    }

    private var windowColor: some View {
        ZStack {
            RadialGradient(
                colors: [InterfaceStyle.sky.opacity(colorScheme == .dark ? 0.28 : 0.25), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 285
            )
            RadialGradient(
                colors: [InterfaceStyle.cobalt.opacity(colorScheme == .dark ? 0.32 : 0.19), .clear],
                center: .trailing,
                startRadius: 10,
                endRadius: 260
            )
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image("BrandIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 54, height: 54)
                .padding(4)
                .modifier(GlassSurface(radius: 17))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("LMFC!")
                    .font(.system(size: 30, weight: .semibold))
                    .tracking(-0.8)
                    .accessibilityAddTraits(.isHeader)
                Text("Let Me F*cking Clean")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)

            HStack(spacing: 6) {
                ForEach(InterfaceLanguage.allCases, id: \.self) { option in
                    Button {
                        language = option
                    } label: {
                        Text(verbatim: option.name)
                            .font(.caption.weight(language == option ? .bold : .medium))
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 36)
                            .contentShape(Capsule())
                    }
                    .modifier(GlassChoiceButton(selected: language == option))
                    .accessibilityAddTraits(language == option ? .isSelected : [])
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Language")
            .frame(width: 148)
            .disabled(session.isActive)
        }
        .padding(.horizontal, 3)
    }

    private var cleaningPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            PanelHeading(
                title: "Cleaning Mode",
                subtitle: "Pause input while you clean your Mac.",
                icon: "keyboard"
            )

            if session.isActive {
                countdown(session.remainingSeconds)
            } else {
                durationPicker

                VStack(spacing: 0) {
                    Toggle(isOn: $blockTrackpad) {
                        ControlRowLabel(title: "Block Trackpad", icon: "trackpad")
                    }
                    Divider().padding(.horizontal, InterfaceStyle.rowInset)
                    Toggle(isOn: $blackOutScreen) {
                        ControlRowLabel(title: "Black Screen", icon: "display")
                    }
                }
                .toggleStyle(AlignedSwitchStyle())
                .modifier(GlassSurface(radius: 15))

                if let requiredPermission {
                    CleaningPermissionView(permission: requiredPermission)
                } else if let statusMessage {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !session.isUntimed {
                Button(action: primaryAction) {
                    Label(actionTitle, systemImage: actionIcon)
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: InterfaceStyle.controlHeight)
                }
                .modifier(GlassPrimaryButton())
                .tint(InterfaceStyle.accent)
                .controlSize(.large)
            }

            Text("Touch ID can still lock your Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .modifier(PanelSurface())
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if let profile = URL(string: "https://github.com/devnisG") {
                Button {
                    openURL(profile)
                } label: {
                    HStack(spacing: 6) {
                        Image("GitHubMark")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 12, height: 12)
                            .foregroundStyle(.primary)
                            .accessibilityHidden(true)
                        Text("Developed by DevnisG")
                    }
                    .frame(minHeight: 28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .modifier(ClickablePointer())
                .accessibilityHint("Opens the DevnisG GitHub profile")
                .disabled(session.isActive)
            }

            if let version = Self.appVersion {
                Text(verbatim: "·")
                    .accessibilityHidden(true)
                Text(verbatim: "v\(version)")
                    .monospacedDigit()
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
    }

    private var durationPicker: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Duration", systemImage: "timer")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            if #available(macOS 26.0, *) {
                GlassEffectContainer(spacing: 5) {
                    HStack(spacing: 7) {
                        ForEach(CleaningSession.durations, id: \.self) { seconds in
                            let isSelected = selectedDuration == seconds
                            Button {
                                duration = seconds
                            } label: {
                                durationLabel(seconds)
                                    .font(.subheadline.weight(isSelected ? .bold : .medium))
                                    .monospacedDigit()
                                    .frame(maxWidth: .infinity)
                                    .frame(minHeight: InterfaceStyle.controlHeight)
                                    .contentShape(.capsule)
                            }
                            .modifier(GlassChoiceButton(selected: isSelected))
                            .disabled(isDurationDisabled(seconds))
                            .accessibilityLabel(seconds.map { Text("\($0) seconds") } ?? Text("No Limit"))
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Duration")
            } else {
                Picker("Duration", selection: Binding(get: { selectedDuration }, set: { option in
                    if !isDurationDisabled(option) { duration = option }
                })) {
                    ForEach(CleaningSession.durations, id: \.self) { seconds in
                        durationLabel(seconds)
                            .tag(seconds)
                            .disabled(isDurationDisabled(seconds))
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
    }

    private var selectedDuration: Int? {
        blockTrackpad && duration != nil ? CleaningSession.pointerDuration : duration
    }

    private func isDurationDisabled(_ seconds: Int?) -> Bool {
        blockTrackpad && seconds != nil && seconds != CleaningSession.pointerDuration
    }

    private func durationLabel(_ seconds: Int?) -> Text {
        seconds.map { Text("\($0) s") } ?? Text("No Limit")
    }

    private func countdown(_ seconds: Int?) -> some View {
        HStack(spacing: 14) {
            Group {
                if let seconds {
                    Text(seconds, format: .number)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: seconds)
                        .accessibilityLabel("\(seconds) seconds remaining")
                } else {
                    Image(systemName: "infinity")
                        .accessibilityLabel("No Limit")
                }
            }
            .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
            .frame(minWidth: 66, minHeight: 56)
            .modifier(GlassSurface(radius: 18))
            VStack(alignment: .leading, spacing: 6) {
                if let statusMessage {
                    Text(statusMessage)
                        .font(.subheadline.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let seconds, let selectedDuration {
                    ProgressView(value: Double(seconds), total: Double(selectedDuration))
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: seconds)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private var actionTitle: LocalizedStringKey {
        if session.isActive { return "Stop Cleaning" }
        return requiredPermission?.title ?? "Start Cleaning"
    }

    private var actionIcon: String {
        if session.isActive { return "stop.fill" }
        return requiredPermission == nil ? "lock.fill" : "lock.shield"
    }

    private var statusMessage: LocalizedStringKey? {
        switch session.state {
        case .secureInput:
            "A secure input field is active. Leave the field and try again."
        case .verifying:
            "Press a letter key to verify the filter."
        case .active where session.isUntimed:
            "Press ⌘⌥⇧U to end cleaning."
        case .active:
            switch session.pointerState {
            case .verifying:
                "Move or click the trackpad to check the filter. ⌘⌥⇧U releases it."
            case .active:
                "Trackpad blocked · Press ⌘⌥⇧U to release"
            case .released:
                "Trackpad available · Keyboard paused"
            case .inactive:
                blackOutScreen ? "Keyboard paused" : "Keyboard filter verified"
            }
        case .unverified:
            "The filter wasn’t verified. Start again and press a letter when prompted."
        case .unavailable:
            "macOS didn’t enable the keyboard filter."
        case .idle, .finished, .interrupted, .permissionRequired, .inputMonitoringRequired:
            nil
        }
    }

    private func primaryAction() {
        if session.isActive {
            session.stop()
        } else if let permission = session.requiredPermission {
            session.requestPermission(permission)
            permission.openSettings()
        } else if duration == nil || blockTrackpad || blackOutScreen {
            confirmCleaning = true
        } else {
            session.start(seconds: duration)
        }
        refresh()
    }

    private var confirmationTitle: LocalizedStringKey {
        if duration == nil { return "Start Cleaning Without a Timer?" }
        return blackOutScreen ? "Turn the Displays Black?" : "Block Trackpad for 30 Seconds?"
    }

    private var confirmationMessage: LocalizedStringKey {
        if duration == nil { return "Press ⌘⌥⇧U to end cleaning and restore input." }
        if blackOutScreen && blockTrackpad {
            return "The displays go black and the trackpad is blocked for up to 30 seconds. Press ⌘⌥⇧U to restore the displays and trackpad."
        }
        if blackOutScreen {
            return "The displays stay black until the timer ends. Click or press ⌘⌥⇧U to restore them early."
        }
        return "Press ⌘⌥⇧U to release the trackpad early. The keyboard stays paused until you click Stop Cleaning or the timer ends. Mouse input may also be blocked."
    }

    private func refresh() {
        session.refresh()
        requiredPermission = session.requiredPermission
    }

    private func workspaceNotification(_ name: Notification.Name) -> NotificationCenter.Publisher {
        NSWorkspace.shared.notificationCenter.publisher(for: name)
    }
}
