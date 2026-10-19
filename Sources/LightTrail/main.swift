// LightTrail — a lightning trail that follows your mouse.
// Transparent, click-through overlay on every screen. No permissions needed.

import AppKit

/// The value after a command-line flag, e.g. `--icon icon.png`.
func argument(after flag: String) -> String? {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
    return args[i + 1]
}

// Developer flags: paint the app icon and the README pictures, then exit.
if let path = argument(after: "--icon") { Showcase.renderIcon(to: path); exit(0) }
if let path = argument(after: "--colors") { Showcase.renderColors(to: path); exit(0) }
if let dir = argument(after: "--demo") { Showcase.renderDemo(toDirectory: dir); exit(0) }

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
