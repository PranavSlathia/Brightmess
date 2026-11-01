import AppKit
import ApplicationServices
import BrightnessCore
import Foundation
import MediaKeyTap

enum BrightnessKeyStatus: Equatable, Sendable {
    case starting
    case needsAccessibility
    case ready
    case conflict(String)
    case unavailable(String)

    var title: String {
        switch self {
        case .starting:
            return "Keyboard brightness keys starting…"
        case .needsAccessibility:
            return "Keyboard keys need Accessibility access"
        case .ready:
            return "Keyboard brightness keys ready"
        case let .conflict(app):
            return "Keyboard keys may conflict with \(app)"
        case let .unavailable(message):
            return "Keyboard keys unavailable: \(message)"
        }
    }

    var needsPermission: Bool {
        self == .needsAccessibility
    }
}

final class BrightnessKeyController: NSObject, MediaKeyTapDelegate, @unchecked Sendable {
    typealias StatusHandler = @Sendable (BrightnessKeyStatus) -> Void

    private let coordinator: DisplayCoordinator
    private var onStatus: StatusHandler?
    private var permissionTimer: DispatchSourceTimer?
    private let repeatLock = NSLock()
    private var lastRepeatAt: TimeInterval = 0

    private lazy var tap = MediaKeyTap(
        delegate: self,
        on: .keyDown,
        for: [.brightnessUp, .brightnessDown],
        observeBuiltIn: true
    )

    init(coordinator: DisplayCoordinator) {
        self.coordinator = coordinator
        super.init()
    }

    func setOnStatus(_ handler: @escaping StatusHandler) {
        onStatus = handler
        publish(.starting)
    }

    func start(prompt: Bool = false) {
        let trusted: Bool
        if prompt {
            let options = [
                kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true,
            ] as CFDictionary
            trusted = AXIsProcessTrustedWithOptions(options)
        } else {
            trusted = AXIsProcessTrusted()
        }

        guard trusted else {
            tap.stop()
            publish(.needsAccessibility)
            if prompt { beginPermissionPolling() }
            return
        }

        permissionTimer?.cancel()
        permissionTimer = nil
        if !tap.started { tap.start() }
        guard tap.started else {
            publish(.unavailable("event tap could not start"))
            return
        }
        if let app = activeConflict() {
            publish(.conflict(app))
        } else {
            publish(.ready)
        }
        RelayLog.write("Magic Keyboard brightness-key tap is active")
    }

    func requestAccessibility() {
        start(prompt: true)
    }

    func stop() {
        permissionTimer?.cancel()
        permissionTimer = nil
        tap.stop()
    }

    func handle(
        mediaKey: MediaKey,
        event keyEvent: KeyEvent?,
        modifiers: NSEvent.ModifierFlags?,
        event: CGEvent
    ) -> CGEvent? {
        guard AXIsProcessTrusted() else {
            publish(.needsAccessibility)
            return event
        }

        let direction: BrightnessStepDirection
        switch mediaKey {
        case .brightnessUp:
            direction = .up
        case .brightnessDown:
            direction = .down
        default:
            return event
        }

        let flags = modifiers ?? []
        if flags.contains(.command) || flags.contains(.control) {
            return event
        }

        let isRepeat = keyEvent?.keyRepeat == true ||
            event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        if isRepeat {
            let now = ProcessInfo.processInfo.systemUptime
            repeatLock.lock()
            defer { repeatLock.unlock() }
            if now - lastRepeatAt < 0.12 { return nil }
            lastRepeatAt = now
        }

        let fine = flags.contains(.option) && flags.contains(.shift)
        coordinator.adjustManualBrightness(direction: direction, fine: fine)
        return nil
    }

    private func beginPermissionPolling() {
        permissionTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            if AXIsProcessTrusted() {
                self.start()
            }
        }
        permissionTimer = timer
        timer.resume()
    }

    private func activeConflict() -> String? {
        let conflicts = [
            "fyi.lunar.Lunar": "Lunar",
            "app.monitorcontrol.MonitorControl": "MonitorControl",
        ]
        for app in NSWorkspace.shared.runningApplications {
            guard let identifier = app.bundleIdentifier,
                  let name = conflicts[identifier]
            else { continue }
            return name
        }
        return nil
    }

    private func publish(_ status: BrightnessKeyStatus) {
        onStatus?(status)
    }
}
