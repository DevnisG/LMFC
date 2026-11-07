import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import IOKit.hidsystem

enum KeyboardEventFilter {
    static let mask: CGEventMask =
        (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        | (1 << CGEventType.flagsChanged.rawValue) | (1 << NX_SYSDEFINED)

    static func isSystemKeyboardSubtype(_ subtype: Int16) -> Bool {
        subtype == NX_SUBTYPE_AUX_CONTROL_BUTTONS || subtype == NX_SUBTYPE_EJECT_KEY
    }

    static func shouldDiscard(_ type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .keyDown, .keyUp, .flagsChanged:
            return true
        default:
            guard type.rawValue == NX_SYSDEFINED,
                  let systemEvent = NSEvent(cgEvent: event), systemEvent.type == .systemDefined else {
                return false
            }
            return isSystemKeyboardSubtype(systemEvent.subtype.rawValue)
        }
    }
}

enum PointerEventFilter {
    static let mask: CGEventMask = [
        CGEventType.mouseMoved,
        .leftMouseDown, .leftMouseUp, .leftMouseDragged,
        .rightMouseDown, .rightMouseUp, .rightMouseDragged,
        .otherMouseDown, .otherMouseUp, .otherMouseDragged,
        .scrollWheel
    ].reduce(0) { $0 | (1 << $1.rawValue) }

    static let gestureMask = NSEvent.EventTypeMask(
        [.gesture, .magnify, .rotate, .swipe, .smartMagnify, .pressure]
    ).rawValue
    static let allEvents = mask | gestureMask

    private static let releaseModifiers: CGEventFlags = [.maskCommand, .maskAlternate, .maskShift]
    private static let shortcutModifiers = releaseModifiers.union([.maskControl, .maskSecondaryFn])

    static func isReleaseShortcut(_ event: CGEvent) -> Bool {
        event.flags.intersection(shortcutModifiers) == releaseModifiers
            && event.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_ANSI_U)
    }
}

@MainActor
final class EventTapKeyboardFilter: KeyboardFilter {
    final class Session {
        let deadline: ContinuousClock.Instant?
        let blockPointer: Bool
        let releaseShortcutEnabled: Bool
        var wasDisabled = false
        var hasBlockedKey = false
        var keyReachedApp = false
        var pointerReleased = false
        var didRequestRelease = false
        var pointerEventDiscarded = false
        private let cursorAnchor: CGPoint?
        private var cursorResetScheduled = false

        var isPointerBlocked: Bool { blockPointer && !pointerReleased }
        var pointerState: PointerLockState {
            guard blockPointer else { return .inactive }
            if pointerReleased { return .released }
            return pointerEventDiscarded ? .active : .verifying
        }

        func blocksPointer(at instant: ContinuousClock.Instant) -> Bool {
            isPointerBlocked && canFilter(at: instant)
        }

        private func canFilter(at instant: ContinuousClock.Instant) -> Bool {
            !wasDisabled && !keyReachedApp && (deadline.map { instant < $0 } ?? true)
        }

        init(
            deadline: ContinuousClock.Instant?,
            blockPointer: Bool,
            releaseShortcutEnabled: Bool = false,
            cursorAnchor: CGPoint? = nil
        ) {
            self.deadline = deadline
            self.blockPointer = blockPointer
            self.releaseShortcutEnabled = blockPointer || releaseShortcutEnabled
            self.cursorAnchor = cursorAnchor
        }

        func shouldDiscard(_ type: CGEventType, event: CGEvent, at instant: ContinuousClock.Instant) -> Bool {
            switch type {
            case .tapDisabledByTimeout, .tapDisabledByUserInput:
                wasDisabled = true
                return false
            default:
                break
            }

            guard canFilter(at: instant) else { return false }
            if KeyboardEventFilter.shouldDiscard(type, event: event) {
                if type == .keyDown {
                    hasBlockedKey = true
                    if releaseShortcutEnabled, !didRequestRelease, PointerEventFilter.isReleaseShortcut(event) {
                        didRequestRelease = true
                        pointerReleased = true
                    }
                }
                return true
            }
            guard isPointerBlocked, PointerEventFilter.allEvents & (1 << type.rawValue) != 0
            else { return false }
            pointerEventDiscarded = true
            switch type {
            case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
                resetCursorIfNeeded(from: event.location)
            default:
                break
            }
            return true
        }

        private func resetCursorIfNeeded(from location: CGPoint) {
            guard !cursorResetScheduled, let cursorAnchor, cursorAnchor != location else { return }
            cursorResetScheduled = true
            CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) { [weak self] in
                guard let self else { return }
                self.cursorResetScheduled = false
                guard self.blocksPointer(at: .now) else { return }
                if CGWarpMouseCursorPosition(cursorAnchor) != .success {
                    self.pointerReleased = true
                }
            }
        }
    }

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var earlyPointerTap: (CFMachPort, CFRunLoopSource)?
    private var session: Session?
    private var localMonitor: Any?

    var hasBlockedKey: Bool { session?.hasBlockedKey == true }
    var pointerState: PointerLockState { session?.pointerState ?? .inactive }
    var didRequestRelease: Bool { session?.didRequestRelease == true }

    var isRunning: Bool {
        guard let tap, let session else { return false }
        return CFMachPortIsValid(tap) && !session.wasDisabled && !session.keyReachedApp
            && CGEvent.tapIsEnabled(tap: tap)
    }

    func start(until deadline: ContinuousClock.Instant?, blockPointer: Bool, releaseShortcutEnabled: Bool) -> Bool {
        stop()
        let cursorAnchor = blockPointer ? CGEvent(source: nil)?.location : nil
        let session = Session(
            deadline: deadline, blockPointer: blockPointer,
            releaseShortcutEnabled: releaseShortcutEnabled, cursorAnchor: cursorAnchor
        )
        let mask = KeyboardEventFilter.mask | (blockPointer ? PointerEventFilter.mask : 0)
        let sessionMask = mask | (blockPointer ? PointerEventFilter.gestureMask : 0)

        guard let (tap, source) = installTap(at: .cgSessionEventTap, mask: sessionMask, session: session)
        else { return false }

        self.session = session
        self.tap = tap
        self.source = source
        guard isRunning, hasRequestedMask(mask) else {
            stop()
            return false
        }

        if blockPointer {
            earlyPointerTap = installTap(at: .cghidEventTap, mask: PointerEventFilter.allEvents, session: session)
        }
        let pointerMask = blockPointer ? NSEvent.EventTypeMask(rawValue: PointerEventFilter.allEvents) : []
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .systemDefined, pointerMask]) { event in
            if event.type == .keyDown
                || (event.type == .systemDefined && KeyboardEventFilter.isSystemKeyboardSubtype(event.subtype.rawValue)) {
                session.keyReachedApp = true
            } else if session.blocksPointer(at: .now),
                      PointerEventFilter.allEvents & (1 << event.type.rawValue) != 0 {
                return nil
            }
            return event
        }
        return true
    }

    private func installTap(
        at location: CGEventTapLocation,
        mask: CGEventMask,
        session: Session
    ) -> (CFMachPort, CFRunLoopSource)? {
        guard let tap = CGEvent.tapCreate(
            tap: location,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let session = Unmanaged<Session>.fromOpaque(context).takeUnretainedValue()

                return session.shouldDiscard(type, event: event, at: ContinuousClock.now)
                    ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(session).toOpaque()
        ) else { return nil }

        guard let source = CFMachPortCreateRunLoopSource(nil, tap, 0) else {
            CFMachPortInvalidate(tap)
            return nil
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return (tap, source)
    }

    func stop() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        localMonitor = nil
        if let (pointerTap, pointerSource) = earlyPointerTap {
            CFMachPortInvalidate(pointerTap)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), pointerSource, .commonModes)
            CFRunLoopSourceInvalidate(pointerSource)
        }
        earlyPointerTap = nil
        if let tap {
            CFMachPortInvalidate(tap)
        }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFRunLoopSourceInvalidate(source)
        }
        source = nil
        tap = nil
        session = nil
    }

    private func hasRequestedMask(_ mask: CGEventMask) -> Bool {
        var count: UInt32 = 0
        guard CGGetEventTapList(0, nil, &count) == .success, count > 0 else { return false }
        let capacity = count + 8
        var taps = Array(repeating: CGEventTapInformation(), count: Int(capacity))
        guard CGGetEventTapList(capacity, &taps, &count) == .success else { return false }
        return taps.prefix(Int(count)).contains { info in
            info.tappingProcess == getpid() && info.tapPoint == .cgSessionEventTap
                && info.options == .defaultTap && info.enabled && (info.eventsOfInterest & mask) == mask
        }
    }
}
