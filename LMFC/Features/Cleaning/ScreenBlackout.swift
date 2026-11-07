import AppKit
import SwiftUI

@MainActor
final class ScreenBlackout {
    private var panels: [NSPanel] = []
    private var previousCursor: NSCursor?

    func show(session: CleaningSession, locale: Locale) -> Bool {
        guard panels.isEmpty else { return true }
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return false }

        previousCursor = NSCursor.current
        panels = screens.map { screen in
            let panel = NSPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isReleasedWhenClosed = false
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.hidesOnDeactivate = true
            panel.isOpaque = true
            panel.hasShadow = false
            panel.backgroundColor = .black
            let view = BlackoutSurface()
            if !session.isUntimed {
                view.onClick = session.revealScreen
            }
            panel.contentView = view
            let countdown = BlackoutCountdownHost(rootView: BlackoutCountdown(session: session, locale: locale))
            countdown.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(countdown)
            NSLayoutConstraint.activate([
                countdown.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                countdown.centerYAnchor.constraint(equalTo: view.centerYAnchor)
            ])
            panel.orderFrontRegardless()
            return panel
        }
        BlackoutSurface.invisibleCursor.set()
        return true
    }

    func hide() {
        for panel in panels {
            panel.close()
        }
        panels.removeAll()
        previousCursor?.set()
        previousCursor = nil
    }
}

private struct BlackoutCountdown: View {
    let session: CleaningSession
    let locale: Locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if session.isActive {
            let showsShortcut = session.isUntimed || session.pointerState == .verifying || session.pointerState == .active
            let captionHeight: CGFloat = showsShortcut ? 114 : 60
            VStack(spacing: 14) {
                Text("LMFC!")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.70))
                    .frame(height: captionHeight, alignment: .bottom)
                    .accessibilityAddTraits(.isHeader)

                Group {
                    if let seconds = session.remainingSeconds {
                        Text(verbatim: String(format: "%d:%02d", seconds / 60, seconds % 60))
                            .contentTransition(.numericText(countsDown: true))
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: seconds)
                            .accessibilityLabel("\(seconds) seconds remaining")
                    } else {
                        Image(systemName: "infinity")
                            .accessibilityLabel("No Limit")
                    }
                }
                .font(.system(size: 56, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white.opacity(0.65))

                VStack(spacing: 10) {
                    Text("Time to Cleaning")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.white.opacity(0.58))

                    if showsShortcut {
                        shortcut
                    }
                }
                .frame(height: captionHeight, alignment: .top)
            }
            .fixedSize()
            .environment(\.locale, locale)
        }
    }

    private var shortcut: some View {
        VStack(spacing: 6) {
            Text(session.isUntimed ? "End Cleaning" : "Unlock Trackpad")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.6))

            HStack(spacing: 8) {
                ForEach(["⌘", "⌥", "⇧", "U"], id: \.self) { key in
                    Text(verbatim: key)
                        .font(.system(size: 30, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.82))
                        .frame(width: 49, height: 46)
                        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(session.isUntimed ? "End Cleaning · ⌘⌥⇧U" : "Unlock Trackpad · ⌘⌥⇧U")
    }
}

private final class BlackoutCountdownHost: NSHostingView<BlackoutCountdown> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class BlackoutSurface: NSView {
    static let invisibleCursor = NSCursor(
        image: NSImage(size: NSSize(width: 1, height: 1), flipped: false) { _ in true },
        hotSpot: .zero
    )
    var onClick: (() -> Void)?

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: Self.invisibleCursor)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        onClick?()
    }
}
