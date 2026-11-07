@preconcurrency import ApplicationServices
import Carbon
import CoreGraphics

@MainActor
struct SystemCleaningAccess: CleaningAccess {
    var isGranted: Bool { AXIsProcessTrusted() }
    var isSecureInputEnabled: Bool { IsSecureEventInputEnabled() }
    var hasInputMonitoring: Bool { CGPreflightListenEventAccess() }

    func requestInputMonitoring() {
        _ = CGRequestListenEventAccess()
    }

    func request() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }
}
