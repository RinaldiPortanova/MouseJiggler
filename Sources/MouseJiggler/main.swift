import AppKit

// Only one copy may run: two copies would take each other's moves for the user's and pause
// each other forever. (A --test run is allowed next to nothing else either.)
let me = Bundle.main.bundleIdentifier ?? "local.mousejiggler"
let others = NSRunningApplication.runningApplications(withBundleIdentifier: me)
    .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
if !others.isEmpty {
    others.first?.activate()
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // menu-bar only, no Dock icon
app.run()
