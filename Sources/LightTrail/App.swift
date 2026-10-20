import AppKit
import ApplicationServices
import ServiceManagement

// MARK: - Overlay windows

final class TrailView: NSView {
    let engine: Engine
    let origin: CGPoint

    init(frame: NSRect, engine: Engine, origin: CGPoint) {
        self.engine = engine
        self.origin = origin
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(dirtyRect)
        ctx.translateBy(x: -origin.x, y: -origin.y)   // draw in global screen coordinates
        Renderer.draw(engine, in: ctx)
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let engine = Engine()
    let finder = TargetFinder()
    let defaults = UserDefaults.standard
    var windows: [NSWindow] = []
    var views: [TrailView] = []
    var timer: Timer?
    var permissionTimer: Timer?
    var statusItem: NSStatusItem?
    var trailItem, strikesItem, iconsItem, allowItem: NSMenuItem?
    var lastDirty = CGRect.null
    var lastMouse = CGPoint.zero
    var lastMoved: CFTimeInterval = 0
    var paused = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        defaults.register(defaults: ["trail": true, "strikes": false, "strikeIcons": false])
        engine.theme = Theme(rawValue: defaults.string(forKey: "theme") ?? "") ?? .red
        engine.trailOn = defaults.bool(forKey: "trail")
        engine.strikesOn = defaults.bool(forKey: "strikes")
        updateIconFinding()
        buildWindows()
        enableLaunchAtLoginOnFirstRun()
        setupStatusItem()
        NotificationCenter.default.addObserver(self, selector: #selector(buildWindows),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        startTimer()
    }

    @objc func buildWindows() {
        windows.forEach { $0.close() }
        windows = []
        views = []
        for screen in NSScreen.screens {
            let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.setFrame(screen.frame, display: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.ignoresMouseEvents = true
            w.isReleasedWhenClosed = false
            w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)))
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            let v = TrailView(frame: CGRect(origin: .zero, size: screen.frame.size), engine: engine, origin: screen.frame.origin)
            w.contentView = v
            if !paused { w.orderFrontRegardless() }
            windows.append(w)
            views.append(v)
        }
    }

    func startTimer() {
        engine.reset(mouse: NSEvent.mouseLocation, time: CACurrentMediaTime())
        let t = Timer(timeInterval: 1.0 / Config.fps, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    @objc func tick() {
        let mouse = NSEvent.mouseLocation
        let now = CACurrentMediaTime()
        if mouse != lastMouse { lastMoved = now }
        lastMouse = mouse
        if engine.strikesOn {
            // Only look around while the mouse is moving; nothing gets struck while it's still.
            if now - lastMoved < 0.3 { finder.update(mouse: mouse, now: now) }
            engine.targets = finder.fresh(now: now)
        }
        engine.step(mouse: mouse, time: now)
        let dirty = engine.bounds()
        let rect = dirty.union(lastDirty)
        lastDirty = dirty
        guard !rect.isNull else { return }
        for v in views {
            let local = rect.offsetBy(dx: -v.origin.x, dy: -v.origin.y).intersection(v.bounds)
            if !local.isNull && !local.isEmpty { v.setNeedsDisplay(local) }
        }
    }

    // MARK: Menu

    func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let bolt = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "LightTrail") {
            bolt.isTemplate = true
            item.button?.image = bolt
        } else {
            item.button?.title = "⚡"
        }
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        let pause = NSMenuItem(title: "Pause", action: #selector(togglePause(_:)), keyEquivalent: "p")
        pause.target = self
        menu.addItem(pause)
        menu.addItem(.separator())

        trailItem = addItem(to: menu, "Trail", #selector(toggleTrail(_:)))
        strikesItem = addItem(to: menu, "Lightning Strikes", #selector(toggleStrikes(_:)))
        strikesItem?.toolTip = "Lightning jumps from the pointer to the edges of nearby windows"
        iconsItem = addItem(to: menu, "Strike Buttons and Icons", #selector(toggleIcons(_:)))
        iconsItem?.indentationLevel = 1
        iconsItem?.toolTip = "Also strike buttons, icons and the Dock. Needs Accessibility permission."
        allowItem = addItem(to: menu, "Allow in Accessibility Settings…", #selector(openAccessibilitySettings))
        allowItem?.indentationLevel = 1
        updateMenu()
        menu.addItem(.separator())

        let colorItem = NSMenuItem(title: "Color", action: nil, keyEquivalent: "")
        let colorMenu = NSMenu()
        for theme in Theme.allCases {
            let mi = NSMenuItem(title: theme.title, action: #selector(chooseTheme(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = theme.rawValue
            mi.image = swatch(theme)
            mi.state = theme == engine.theme ? .on : .off
            colorMenu.addItem(mi)
        }
        colorItem.submenu = colorMenu
        menu.addItem(colorItem)
        let login = NSMenuItem(title: "Start at Login", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit LightTrail", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    func addItem(to menu: NSMenu, _ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateIconFinding()
        updateMenu()
    }

    func updateMenu() {
        let wantsIcons = defaults.bool(forKey: "strikeIcons")
        let waiting = wantsIcons && !AXIsProcessTrusted()
        trailItem?.state = engine.trailOn ? .on : .off
        strikesItem?.state = engine.strikesOn ? .on : .off
        iconsItem?.state = waiting ? .mixed : wantsIcons ? .on : .off
        iconsItem?.isEnabled = engine.strikesOn
        allowItem?.isHidden = !(waiting && engine.strikesOn)
    }

    @objc func toggleTrail(_ sender: NSMenuItem) {
        engine.trailOn.toggle()
        defaults.set(engine.trailOn, forKey: "trail")
        updateMenu()
    }

    @objc func toggleStrikes(_ sender: NSMenuItem) {
        engine.strikesOn.toggle()
        defaults.set(engine.strikesOn, forKey: "strikes")
        if !engine.strikesOn { engine.targets = Targets() }
        updateIconFinding()
        updateMenu()
    }

    @objc func toggleIcons(_ sender: NSMenuItem) {
        let on = !defaults.bool(forKey: "strikeIcons")
        defaults.set(on, forKey: "strikeIcons")
        if on && !AXIsProcessTrusted() {
            // The system prompt that leads to Privacy & Security > Accessibility.
            let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
        }
        updateIconFinding()
        updateMenu()
    }

    @objc func openAccessibilitySettings() {
        let url = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: url) { NSWorkspace.shared.open(url) }
    }

    /// Buttons and icons are only looked for when they're switched on and Accessibility is allowed.
    /// While waiting for the permission, check every couple of seconds so it starts working without a restart.
    func updateIconFinding() {
        let wanted = engine.strikesOn && defaults.bool(forKey: "strikeIcons")
        let trusted = wanted && AXIsProcessTrusted()
        finder.findsElements = trusted
        if wanted && !trusted {
            guard permissionTimer == nil else { return }
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                guard AXIsProcessTrusted() else { return }
                self?.updateIconFinding()
                self?.updateMenu()
            }
        } else {
            permissionTimer?.invalidate()
            permissionTimer = nil
        }
    }

    @objc func chooseTheme(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let theme = Theme(rawValue: raw) else { return }
        engine.theme = theme
        defaults.set(raw, forKey: "theme")
        sender.menu?.items.forEach { $0.state = $0 === sender ? .on : .off }
    }

    func swatch(_ theme: Theme) -> NSImage {
        NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            let oval = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            if theme == .rainbow {
                let hues = stride(from: 0.0, through: 1.0, by: 0.2).map { Theme.hue(CGFloat($0)).ns }
                NSGradient(colors: hues)?.draw(in: oval, angle: 0)
            } else {
                theme.base(at: 0).ns.setFill()
                oval.fill()
            }
            return true
        }
    }

    func enableLaunchAtLoginOnFirstRun() {
        let key = "didSetUpLaunchAtLogin"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        try? SMAppService.mainApp.register()
    }

    @objc func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            NSLog("LightTrail: launch-at-login change failed: \(error)")
        }
        sender.state = service.status == .enabled ? .on : .off
    }

    @objc func togglePause(_ sender: NSMenuItem) {
        paused.toggle()
        sender.title = paused ? "Resume" : "Pause"
        if paused {
            timer?.invalidate()
            timer = nil
            windows.forEach { $0.orderOut(nil) }
        } else {
            engine.clear()
            windows.forEach { $0.orderFrontRegardless() }
            startTimer()
        }
    }
}
