import Foundation
import Observation

@MainActor
protocol KeyboardFilter: AnyObject {
    var isRunning: Bool { get }
    var hasBlockedKey: Bool { get }
    var pointerState: PointerLockState { get }
    var didRequestRelease: Bool { get }
    func start(until deadline: ContinuousClock.Instant?, blockPointer: Bool, releaseShortcutEnabled: Bool) -> Bool
    func stop()
}

@MainActor
protocol CleaningAccess {
    var isGranted: Bool { get }
    var isSecureInputEnabled: Bool { get }
    var hasInputMonitoring: Bool { get }
    func request()
    func requestInputMonitoring()
}

enum CleaningPermission: Equatable {
    case accessibility
    case inputMonitoring
}

enum PointerLockState {
    case inactive
    case verifying
    case active
    case released
}

@MainActor
@Observable
final class CleaningSession {
    enum State: Equatable {
        case idle
        case permissionRequired
        case inputMonitoringRequired
        case secureInput
        case verifying(remainingSeconds: Int?)
        case active(remainingSeconds: Int?)
        case unverified
        case finished
        case interrupted
        case unavailable
    }

    static let durations: [Int?] = [30, 60, 90, nil]
    static let pointerDuration = 30

    private(set) var state: State = .idle
    private(set) var pointerState: PointerLockState = .inactive
    private(set) var isScreenBlackoutActive = false
    private let filter: any KeyboardFilter
    private let access: any CleaningAccess
    private let now: () -> ContinuousClock.Instant
    private var deadline: ContinuousClock.Instant?
    private var verificationDeadline: ContinuousClock.Instant?
    private var timer: Task<Void, Never>?

    init(
        filter: any KeyboardFilter,
        access: any CleaningAccess,
        now: @escaping () -> ContinuousClock.Instant = { ContinuousClock.now }
    ) {
        self.filter = filter
        self.access = access
        self.now = now
    }

    var isActive: Bool {
        switch state {
        case .verifying, .active: true
        default: false
        }
    }

    var isUntimed: Bool { isActive && deadline == nil }

    var remainingSeconds: Int? {
        switch state {
        case .verifying(let seconds), .active(let seconds): seconds
        default: nil
        }
    }

    var requiredPermission: CleaningPermission? {
        if !access.isGranted { return .accessibility }
        if state == .inputMonitoringRequired, !access.hasInputMonitoring { return .inputMonitoring }
        return nil
    }

    func requestPermission(_ permission: CleaningPermission) {
        guard !isActive else { return }
        switch permission {
        case .accessibility:
            guard !access.isGranted else { return }
            state = .permissionRequired
            access.request()
        case .inputMonitoring:
            guard !access.hasInputMonitoring else { return }
            state = .inputMonitoringRequired
            access.requestInputMonitoring()
        }
    }

    func start(seconds: Int?, blockPointer: Bool = false, blackoutScreen: Bool = false) {
        guard !isActive, Self.durations.contains(seconds) else { return }
        guard access.isGranted else {
            requestPermission(.accessibility)
            return
        }
        guard !access.isSecureInputEnabled else {
            state = .secureInput
            return
        }

        let start = now()
        let duration = seconds.map { blockPointer ? Self.pointerDuration : $0 }
        let end = duration.map { start.advanced(by: .seconds($0)) }
        guard filter.start(
            until: end, blockPointer: blockPointer, releaseShortcutEnabled: end == nil || blockPointer || blackoutScreen
        ), filter.isRunning else {
            if access.hasInputMonitoring {
                finish(as: .unavailable)
            } else {
                finish(as: .inputMonitoringRequired)
                requestPermission(.inputMonitoring)
            }
            return
        }

        deadline = end
        isScreenBlackoutActive = blackoutScreen
        verificationDeadline = end == nil || blockPointer || blackoutScreen ? nil : start.advanced(by: .seconds(8))
        state = .verifying(remainingSeconds: duration)
        refresh()
        guard isActive else { return }
        timer = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(200))
                } catch {
                    return
                }
                self?.refresh()
                guard self?.isActive == true else { return }
            }
        }
    }

    func stop() {
        guard isActive else { return }
        finish(as: .finished)
    }

    func interrupt() {
        guard isActive else { return }
        finish(as: .interrupted)
    }

    func revealScreen() {
        isScreenBlackoutActive = false
    }

    func refresh() {
        guard isActive else {
            if (state == .permissionRequired || state == .inputMonitoringRequired), requiredPermission == nil {
                state = .idle
            }
            return
        }

        let instant = now()
        let remaining = deadline.map { instant.duration(to: $0) }
        if let remaining, remaining <= .zero {
            finish(as: .finished)
            return
        }
        guard filter.isRunning, access.isGranted, !access.isSecureInputEnabled else {
            finish(as: .interrupted)
            return
        }

        pointerState = filter.pointerState
        if filter.didRequestRelease {
            if isUntimed {
                finish(as: .finished)
                return
            }
            revealScreen()
        }
        let remainingSeconds = remaining.map {
            let (seconds, attoseconds) = $0.components
            return Int(seconds) + (attoseconds > 0 ? 1 : 0)
        }
        if verificationDeadline == nil || filter.hasBlockedKey {
            verificationDeadline = nil
            state = .active(remainingSeconds: remainingSeconds)
        } else if let verificationDeadline, instant >= verificationDeadline {
            finish(as: .unverified)
        } else {
            state = .verifying(remainingSeconds: remainingSeconds)
        }
    }

    private func finish(as result: State) {
        filter.stop()
        pointerState = .inactive
        revealScreen()
        timer?.cancel()
        timer = nil
        deadline = nil
        verificationDeadline = nil
        state = result
    }
}
