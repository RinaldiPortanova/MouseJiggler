import AppKit
import ApplicationServices
import CoreGraphics

/// Keeps the Mac from going idle by gliding the pointer a few pixels now
/// and then, and keeps out of the way while the user uses the Mac.
///
/// How it tells "me" from "the user":
/// - pointer moves: it remembers where it put the pointer. Any other position means the user
///   moved the mouse or the trackpad;
/// - keys, clicks, scrolls, held buttons: macOS counts the seconds since the last event of each
///   type. The app itself only ever sends "pointer moved" events, so these are always the user.
final class Jiggler {
    enum Mode: Equatable {
        case running        // jiggling: next small move at `nextMoveAt`
        case userActive     // the user is using the Mac: resume `resumeDelay` s after the last input
        case pausedByUser   // paused from the menu
        case screenLocked   // screen locked, screensaver on, or another user session: never jiggle
    }

    struct Settings {
        var resumeDelay: TimeInterval = 5
        var interval: ClosedRange<TimeInterval> = 15...40   // random pause between two moves
        var radius: Double = 25         // max distance (points) from where the pointer was left
        var minStep: Double = 6         // never a move shorter than this
        var glideDuration: TimeInterval = 0.4
        var edgeMargin: Double = 12     // stay away from screen edges (Dock, hot corners)
    }

    var settings = Settings()
    var log: (String) -> Void = { _ in }
    var onChange: () -> Void = {}
    /// Called after each completed move with the move's target (used by --test).
    var onMoved: (CGPoint) -> Void = { _ in }

    private(set) var mode: Mode = .userActive
    private(set) var nextMoveAt = Date()
    private(set) var lastUserInput = Date()     // launching the app is itself user input
    private(set) var hasAccessibility = AXIsProcessTrusted()
    private(set) var movesSinceResume = 0
    var isGliding: Bool { glide != nil }

    private var manuallyPaused = false
    private var screenLocked = false
    private var screensaverOn = false
    private var sessionInactive = false

    private var home = CGPoint.zero             // where the user left the pointer
    private var expected: CGPoint?              // where the pointer should be if nobody touched it
    private var recent: [(point: CGPoint, at: Date)] = []   // points we sent in the last moments
    private var tickTimer: Timer?
    private var glideTimer: Timer?
    private var glide: (from: CGPoint, to: CGPoint, step: Int, steps: Int)?
    private var lastTrustCheck = Date.distantPast

    /// Our own event source. `localEventsSuppressionInterval = 0`: macOS must not ignore the real
    /// mouse for a moment after each of our events, so grabbing the mouse mid-glide just works.
    private let source: CGEventSource? = {
        let s = CGEventSource(stateID: .hidSystemState)
        s?.localEventsSuppressionInterval = 0
        return s
    }()

    /// Event types the app never sends itself: any of them means the user is there.
    /// Trackpad gestures have no named constant: 29 = gesture, 30 = pinch, 31 = swipe.
    /// Never add types 32 and above: measured on macOS 27.2, macOS answers them with the
    /// "any input" counter, so the app's own moves would look like the user (it paused itself
    /// after every move). Types 18-20 are never updated.
    private static let userEventTypes: [CGEventType] = [
        .keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown,
        .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel,
        CGEventType(rawValue: 29)!, CGEventType(rawValue: 30)!, CGEventType(rawValue: 31)!,
    ]

    /// Why the app last thought the user was there (written to the log, for diagnosis).
    private var inputReason = "app started"
    /// Keeps macOS from slowing the app's timers down (App Nap) while it sits in the menu bar.
    private var activity: NSObjectProtocol?

    // MARK: - Start / pause

    func start() {
        expected = cursorPosition()
        activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep, reason: "MouseJiggler timers")
        observeLockAndSleep()
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = 0.05
        RunLoop.main.add(t, forMode: .common)   // .common: keeps running while the menu is open
        tickTimer = t
        log("started (accessibility: \(hasAccessibility ? "yes" : "NO"))")
        tick()
    }

    func setPaused(_ paused: Bool) {
        manuallyPaused = paused
        log(paused ? "paused from the menu" : "resumed from the menu")
        tick()
    }

    var isManuallyPaused: Bool { manuallyPaused }

    // MARK: - The 4-times-a-second check

    private func tick() {
        let now = Date()
        if now.timeIntervalSince(lastTrustCheck) > 2 {
            lastTrustCheck = now
            let trusted = AXIsProcessTrusted()
            if trusted != hasAccessibility {
                hasAccessibility = trusted
                log("accessibility permission \(trusted ? "granted" : "REMOVED")")
            }
        }
        let pos = cursorPosition()
        noteUserInput(now: now, pos: pos)

        let newMode: Mode
        if screenLocked || screensaverOn || sessionInactive { newMode = .screenLocked }
        else if manuallyPaused { newMode = .pausedByUser }
        else if now.timeIntervalSince(lastUserInput) < settings.resumeDelay { newMode = .userActive }
        else { newMode = .running }

        if newMode != mode {
            if mode == .running { stopGlide() }
            if newMode == .running {
                home = pos
                nextMoveAt = now   // the first move comes right when the 5 s are over
                movesSinceResume = 0
            }
            log("mode \(Self.name(mode)) → \(Self.name(newMode))"
                + (mode == .running ? " (\(movesSinceResume) moves)" : "")
                + (newMode == .userActive ? ": \(inputReason)" : ""))
            mode = newMode
        }

        if mode == .running, glide == nil, hasAccessibility, now >= nextMoveAt {
            startGlide(from: pos)
        }
        onChange()
    }

    /// Updates `lastUserInput` from the pointer position and from macOS's per-type idle counters.
    private func noteUserInput(now: Date, pos: CGPoint) {
        recent.removeAll { now.timeIntervalSince($0.at) > 0.5 }
        if let e = expected, distance(pos, e) > 2, !recent.contains(where: { distance(pos, $0.point) <= 2 }) {
            // the pointer is somewhere we did not put it
            markInput(now, String(format: "pointer moved to (%.0f,%.0f) from (%.0f,%.0f)", pos.x, pos.y, e.x, e.y))
        }
        expected = pos

        for type in Self.userEventTypes {
            let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: type)
            if idle.isFinite, idle >= 0 {
                markInput(now.addingTimeInterval(-idle), "event type \(type.rawValue) \(String(format: "%.1f", idle)) s ago")
            }
        }

        for button in [CGMouseButton.left, .right, .center]
        where CGEventSource.buttonState(.combinedSessionState, button: button) {
            markInput(now, "mouse button held")   // e.g. a slow drag
        }
    }

    private func markInput(_ at: Date, _ reason: @autoclosure () -> String) {
        guard at > lastUserInput else { return }
        lastUserInput = at
        inputReason = reason()
    }

    // MARK: - The small glide

    private func startGlide(from pos: CGPoint) {
        let target = pickTarget(from: pos)
        let steps = max(2, Int(settings.glideDuration * 60))
        glide = (pos, target, 0, steps)
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.glideStep() }
        RunLoop.main.add(t, forMode: .common)
        glideTimer = t
    }

    private func glideStep() {
        guard var g = glide else { return }
        let pos = cursorPosition()
        if let e = expected, distance(pos, e) > 2, !recent.contains(where: { distance(pos, $0.point) <= 2 }) {
            // The user grabbed the mouse mid-glide: give it back at once.
            stopGlide()
            markInput(Date(), "pointer grabbed during a glide")
            expected = pos
            tick()
            return
        }
        g.step += 1
        let t = Double(g.step) / Double(g.steps)
        let e = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2     // ease in-out
        let p = CGPoint(x: g.from.x + (g.to.x - g.from.x) * e, y: g.from.y + (g.to.y - g.from.y) * e)
        post(p)
        if g.step >= g.steps {
            stopGlide()
            movesSinceResume += 1
            nextMoveAt = Date().addingTimeInterval(.random(in: settings.interval))
            onMoved(g.to)
            onChange()
        } else {
            glide = g
        }
    }

    private func stopGlide() {
        glideTimer?.invalidate()
        glideTimer = nil
        glide = nil
    }

    /// Sends one real "pointer moved" event: for macOS (and other apps) it is the mouse.
    private func post(_ p: CGPoint) {
        recent.append((p, Date()))
        expected = p
        CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
                mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    /// A random point at most `radius` from where the user left the pointer, never too close to
    /// the current position, never at a screen edge.
    private func pickTarget(from pos: CGPoint) -> CGPoint {
        for _ in 0..<12 {
            let angle = Double.random(in: 0..<(2 * .pi))
            let r = settings.radius * sqrt(Double.random(in: 0...1))
            let t = clamp(CGPoint(x: (home.x + r * cos(angle)).rounded(),
                                  y: (home.y + r * sin(angle)).rounded()))
            if distance(t, pos) >= settings.minStep { return t }
        }
        let t = clamp(CGPoint(x: home.x + settings.minStep, y: home.y))
        return distance(t, pos) >= 1 ? t : clamp(CGPoint(x: home.x - settings.minStep, y: home.y))
    }

    private func clamp(_ p: CGPoint) -> CGPoint {
        var display = CGDirectDisplayID()
        var count: UInt32 = 0
        CGGetDisplaysWithPoint(home, 1, &display, &count)
        let bounds = CGDisplayBounds(count > 0 ? display : CGMainDisplayID())
            .insetBy(dx: settings.edgeMargin, dy: settings.edgeMargin)
        return CGPoint(x: min(max(p.x, bounds.minX), bounds.maxX),
                       y: min(max(p.y, bounds.minY), bounds.maxY))
    }

    // MARK: - Lock, screensaver, sleep

    private func observeLockAndSleep() {
        let dnc = DistributedNotificationCenter.default()
        let pairs: [(String, ReferenceWritableKeyPath<Jiggler, Bool>, Bool)] = [
            ("com.apple.screenIsLocked", \.screenLocked, true),
            ("com.apple.screenIsUnlocked", \.screenLocked, false),
            ("com.apple.screensaver.didstart", \.screensaverOn, true),
            ("com.apple.screensaver.didstop", \.screensaverOn, false),
        ]
        for (name, key, value) in pairs {
            dnc.addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] _ in
                self?.setFlag(key, value, name)
            }
        }
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.setFlag(\.sessionInactive, true, "session inactive")
        }
        ws.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.setFlag(\.sessionInactive, false, "session active")
        }
        ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.log("woke from sleep")
            self?.markInput(Date(), "woke from sleep")
            self?.expected = self?.cursorPosition()
        }
    }

    private func setFlag(_ key: ReferenceWritableKeyPath<Jiggler, Bool>, _ value: Bool, _ name: String) {
        self[keyPath: key] = value
        if !value {
            // Coming back (unlock, screensaver off): count it as user input, so the first move
            // waits the usual 5 s.
            markInput(Date(), name)
            expected = cursorPosition()
        }
        log("event: \(name)")
        tick()
    }

    // MARK: - Helpers

    func cursorPosition() -> CGPoint { CGEvent(source: nil)?.location ?? .zero }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> Double { hypot(a.x - b.x, a.y - b.y) }

    static func name(_ m: Mode) -> String {
        switch m {
        case .running: return "running"
        case .userActive: return "user-active"
        case .pausedByUser: return "paused"
        case .screenLocked: return "locked"
        }
    }
}
