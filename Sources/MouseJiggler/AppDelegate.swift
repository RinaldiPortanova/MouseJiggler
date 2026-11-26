import AppKit
import ApplicationServices

/// Appends timestamped lines to ~/Library/Logs/MouseJiggler.log. Past 1 MB the file becomes
/// MouseJiggler.old.log (replacing the previous one), so the log never grows without limit.
final class AppLog {
    private let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/MouseJiggler.log")

    func callAsFunction(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        let fm = FileManager.default
        if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 1_000_000 {
            let old = url.deletingPathExtension().appendingPathExtension("old.log")
            try? fm.removeItem(at: old)
            try? fm.moveItem(at: url, to: old)
        }
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(data); try? h.close()
        } else {
            try? data.write(to: url)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let log = AppLog()
    private let jiggler = Jiggler()
    private var statusItem: NSStatusItem!
    private weak var statusLine: NSMenuItem?
    private var shownSymbol = ""

    // --test mode
    private var testSeconds: Double?
    private var logIdle = false

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        parseArguments()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu

        jiggler.log = { [weak self] in self?.log($0) }
        jiggler.onChange = { [weak self] in self?.refresh() }
        if logIdle { jiggler.onMoved = { [weak self] target in self?.logIdleCounters(target) } }

        log("launched (macOS \(ProcessInfo.processInfo.operatingSystemVersionString))"
            + (testSeconds.map { " TEST \($0)s, interval \(jiggler.settings.interval), resume \(jiggler.settings.resumeDelay)s" } ?? ""))
        jiggler.start()
        if !jiggler.hasAccessibility { askForAccessibility() }

        if let seconds = testSeconds {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
                self?.log("test finished")
                NSApp.terminate(nil)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        log("quit")
    }

    private func parseArguments() {
        let args = CommandLine.arguments
        func value(after flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        testSeconds = value(after: "--test").flatMap(Double.init)
        logIdle = args.contains("--log-idle")
        if let r = value(after: "--resume").flatMap(Double.init) { jiggler.settings.resumeDelay = r }
        if let i = value(after: "--interval") {          // e.g. "2-4"
            let parts = i.split(separator: "-").compactMap { Double($0) }
            if parts.count == 2, parts[0] <= parts[1] { jiggler.settings.interval = parts[0]...parts[1] }
        }
    }

    // MARK: - Accessibility permission

    /// Shows macOS's own "MouseJiggler would like to control this computer" prompt, which has an
    /// "Open System Settings" button. Without this permission macOS silently drops the moves.
    private func askForAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    @objc private func openAccessibilitySettings() {
        askForAccessibility()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Menu bar icon and menu

    private var statusText: String {
        switch jiggler.mode {
        case .screenLocked:
            return "Paused: screen locked"
        case .pausedByUser:
            return "Paused"
        case .userActive:
            return jiggler.hasAccessibility
                ? "Paused: you are using the Mac (resumes \(Int(jiggler.settings.resumeDelay)) s after you stop)"
                : "Accessibility permission missing: the pointer can't move"
        case .running:
            guard jiggler.hasAccessibility else { return "Accessibility permission missing: the pointer can't move" }
            if jiggler.isGliding { return "Active: moving the pointer" }
            let s = max(0, Int(jiggler.nextMoveAt.timeIntervalSinceNow.rounded(.up)))
            return "Active: next move in \(s) s"
        }
    }

    private var symbol: String {
        switch jiggler.mode {
        case .screenLocked: return "lock"
        case .pausedByUser: return "pause.circle"
        case _ where !jiggler.hasAccessibility: return "exclamationmark.triangle"
        case .userActive: return "cursorarrow"
        case .running: return "cursorarrow.motionlines"
        }
    }

    private func refresh() {
        guard let button = statusItem?.button else { return }
        let name = symbol
        if name != shownSymbol {
            shownSymbol = name
            let image = NSImage(systemSymbolName: name, accessibilityDescription: "MouseJiggler")
            image?.isTemplate = true
            button.image = image
        }
        let text = statusText
        button.toolTip = "MouseJiggler: \(text)"
        if statusLine?.title != text { statusLine?.title = text }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let line = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
        line.isEnabled = false
        menu.addItem(line)
        statusLine = line
        menu.addItem(.separator())

        let paused = jiggler.isManuallyPaused
        let toggle = NSMenuItem(title: paused ? "Resume" : "Pause",
                                action: #selector(togglePause), keyEquivalent: "p")
        toggle.target = self
        menu.addItem(toggle)

        if !jiggler.hasAccessibility {
            let perm = NSMenuItem(title: "Grant Accessibility Permission…",
                                  action: #selector(openAccessibilitySettings), keyEquivalent: "")
            perm.target = self
            menu.addItem(perm)
        }

        menu.addItem(.separator())
        let info = NSMenuItem(title: "Pauses while you use the mouse or keyboard, resumes after \(Int(jiggler.settings.resumeDelay)) s",
                              action: nil, keyEquivalent: "")
        info.isEnabled = false
        menu.addItem(info)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit MouseJiggler", action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        menu.addItem(quit)
    }

    @objc private func togglePause() {
        jiggler.setPaused(!jiggler.isManuallyPaused)
    }

    // MARK: - --log-idle (test)

    /// After each move, what macOS (and so other apps) sees as "seconds since the last input".
    private func logIdleCounters(_ target: CGPoint) {
        let any = CGEventType(rawValue: ~0)!
        let combined = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: any)
        let hid = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: any)
        let pos = jiggler.cursorPosition()
        log(String(format: "moved to (%.0f,%.0f), pointer at (%.0f,%.0f), idle combined=%.2fs hid=%.2fs",
                   target.x, target.y, pos.x, pos.y, combined, hid))
    }
}
