import AppKit

/// Tracks keyboard activity without recording keystrokes — only whether
/// the user is currently typing. Used to suppress notification sounds while
/// the user is typing, with a 5s debounce after the last keystroke before
/// resuming notifications.
///
/// Privacy: No keystrokes are captured, stored, or transmitted. The monitor
/// only records the timestamp of the most recent key-down event.
@MainActor
final class KeyboardActivityMonitor {
    static let shared = KeyboardActivityMonitor()

    /// Seconds after the last keystroke before notifications resume.
    static let debounceInterval: TimeInterval = 5

    /// Timestamp of the most recent key-down event (main-thread only).
    private(set) var lastKeydownAt: Date?

    /// True if the user has typed within the debounce window.
    var isTyping: Bool {
        guard let last = lastKeydownAt else { return false }
        return Date().timeIntervalSince(last) < Self.debounceInterval
    }

    private var globalMonitor: Any?
    private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        // Global monitor fires for key-down events even when the app is not
        // focused. We only record the timestamp — no key content is captured.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] _ in
            self?.lastKeydownAt = Date()
        }
    }

    func stop() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        started = false
        lastKeydownAt = nil
    }
}
