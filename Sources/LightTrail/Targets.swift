import AppKit
import ApplicationServices

// MARK: - What lightning can strike

/// A straight piece of a window's outline that you can actually see, in screen points (y up, like the mouse).
struct Edge {
    var a: CGPoint
    var b: CGPoint

    /// The point on the edge closest to `p`, moved `slide` points along the edge (but never past its ends).
    func point(near p: CGPoint, slide: CGFloat = 0) -> CGPoint {
        let dx = b.x - a.x, dy = b.y - a.y
        let len = hypot(dx, dy)
        guard len > 0 else { return a }
        let t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / (len * len) + slide / len
        let c = max(0, min(1, t))
        return CGPoint(x: a.x + dx * c, y: a.y + dy * c)
    }

    /// Unit vector from `a` to `b`.
    var direction: CGVector {
        let dx = b.x - a.x, dy = b.y - a.y
        let len = max(hypot(dx, dy), 0.001)
        return CGVector(dx: dx / len, dy: dy / len)
    }
}

/// Everything the lightning can jump to right now.
struct Targets {
    var edges: [Edge] = []
    /// Buttons and icons, found only when Accessibility is allowed.
    var elements: [CGRect] = []
}

/// A window as far as lightning cares: where it is, and whether its outline can be struck.
/// Windows that fill a whole display still hide what's behind them, but have no edges worth striking.
struct WindowShape {
    var frame: CGRect
    var strikable: Bool
}

enum WindowEdges {
    /// Rounded window corners leave empty space at the very corner, so edges stop this far short of it.
    static let corner: CGFloat = 10

    /// The parts of each window's outline that no other window covers. `windows` is front to back.
    static func visible(of windows: [WindowShape], screens: [CGRect]) -> [Edge] {
        var edges: [Edge] = []
        for (i, w) in windows.enumerated() where w.strikable {
            let r = w.frame
            guard r.width > corner * 3, r.height > corner * 3 else { continue }
            let c = corner
            // Each side, with the direction that points away from the window.
            let sides: [(Edge, CGVector)] = [
                (Edge(a: CGPoint(x: r.minX + c, y: r.maxY), b: CGPoint(x: r.maxX - c, y: r.maxY)), CGVector(dx: 0, dy: 1)),
                (Edge(a: CGPoint(x: r.minX + c, y: r.minY), b: CGPoint(x: r.maxX - c, y: r.minY)), CGVector(dx: 0, dy: -1)),
                (Edge(a: CGPoint(x: r.minX, y: r.minY + c), b: CGPoint(x: r.minX, y: r.maxY - c)), CGVector(dx: -1, dy: 0)),
                (Edge(a: CGPoint(x: r.maxX, y: r.minY + c), b: CGPoint(x: r.maxX, y: r.maxY - c)), CGVector(dx: 1, dy: 0)),
            ]
            for (side, out) in sides {
                // Skip sides that sit on the border of a display (its bezel, or where two displays meet):
                // just inside and just outside the side have to be on the same display.
                let mid = CGPoint(x: (side.a.x + side.b.x) / 2, y: (side.a.y + side.b.y) / 2)
                let inside = CGPoint(x: mid.x - out.dx * 3, y: mid.y - out.dy * 3)
                let beyond = CGPoint(x: mid.x + out.dx * 3, y: mid.y + out.dy * 3)
                guard screens.contains(where: { $0.contains(inside) && $0.contains(beyond) }) else { continue }
                edges += uncovered(side, by: windows[..<i].map(\.frame))
            }
        }
        return edges
    }

    /// Cuts out the stretches of an axis-aligned edge that lie under any of `covers`.
    private static func uncovered(_ edge: Edge, by covers: [CGRect]) -> [Edge] {
        let horizontal = edge.a.y == edge.b.y
        let fixed = horizontal ? edge.a.y : edge.a.x
        var pieces = [(lo: horizontal ? edge.a.x : edge.a.y, hi: horizontal ? edge.b.x : edge.b.y)]
        for f in covers {
            let (across, along) = horizontal ? (f.minY...f.maxY, (f.minX, f.maxX)) : (f.minX...f.maxX, (f.minY, f.maxY))
            guard across.contains(fixed) else { continue }
            pieces = pieces.flatMap { p -> [(lo: CGFloat, hi: CGFloat)] in
                if along.1 <= p.lo || along.0 >= p.hi { return [p] }
                var rest: [(lo: CGFloat, hi: CGFloat)] = []
                if along.0 > p.lo { rest.append((p.lo, along.0)) }
                if along.1 < p.hi { rest.append((along.1, p.hi)) }
                return rest
            }
            if pieces.isEmpty { return [] }
        }
        return pieces.filter { $0.hi - $0.lo >= 16 }.map { p in
            horizontal ? Edge(a: CGPoint(x: p.lo, y: fixed), b: CGPoint(x: p.hi, y: fixed))
                       : Edge(a: CGPoint(x: fixed, y: p.lo), b: CGPoint(x: fixed, y: p.hi))
        }
    }

    /// Visible window edges on screen right now. Window positions don't need any permission.
    /// `flip` is the height of the main display: window and Accessibility coordinates have y pointing down.
    static func onScreen(screens: [CGRect], flip: CGFloat) -> [Edge] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return [] }
        let me = getpid()
        let dockLayer = Int(CGWindowLevelForKey(.dockWindow))
        let overlayLayer = Int(CGWindowLevelForKey(.overlayWindow))
        var shapes: [WindowShape] = []
        for w in list {
            guard let pid = w[kCGWindowOwnerPID as String] as? Int32, pid != me,
                  let layer = w[kCGWindowLayer as String] as? Int,
                  // Skip the Dock's invisible full-screen layer, and overlays like this app's own windows.
                  layer != dockLayer, layer < overlayLayer,
                  let dict = w[kCGWindowBounds as String] as? NSDictionary,
                  let b = CGRect(dictionaryRepresentation: dict as CFDictionary),
                  (w[kCGWindowAlpha as String] as? Double ?? 1) > 0.05,
                  b.width >= 24, b.height >= 16 else { continue }
            let frame = CGRect(x: b.minX, y: flip - b.maxY, width: b.width, height: b.height)
            let fillsScreen = screens.contains { frame.insetBy(dx: -2, dy: -2).contains($0) }
            // Above normal windows, a window that covers a whole display is an invisible layer, not a real window.
            if fillsScreen && layer != 0 { continue }
            shapes.append(WindowShape(frame: frame, strikable: !fillsScreen))
        }
        return visible(of: shapes, screens: screens)
    }
}

// MARK: - Buttons and icons (needs Accessibility)

/// Finds buttons and icons near the pointer by asking Accessibility what's under a few random spots around it
/// each scan. Found elements are remembered for a moment, so the area around the pointer fills in quickly.
/// Only used from `TargetFinder`'s background queue.
final class ElementProbe {
    static let roles: Set<String> = [
        "AXButton", "AXImage", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton", "AXMenuBarItem",
        "AXDockItem", "AXLink", "AXDisclosureTriangle", "AXComboBox", "AXSlider", "AXIncrementor", "AXTextField",
        "AXColorWell",
    ]
    /// Rows of icons (the menu bar, the Dock, toolbars): when one of these is hit, take all its icons at once.
    static let rows: Set<String> = ["AXMenuBar", "AXList", "AXToolbar"]

    private let system = AXUIElementCreateSystemWide()
    private var found: [(frame: CGRect, seen: CFTimeInterval)] = []
    private var expandedRows: [(frame: CGRect, at: CFTimeInterval)] = []

    init() {
        // Applies to every Accessibility call: never wait long on an app that's busy.
        AXUIElementSetMessagingTimeout(system, 0.05)
    }

    func scan(around mouse: CGPoint, reach: CGFloat, flip: CGFloat, now: CFTimeInterval, probes: Int = 6) -> [CGRect] {
        found.removeAll { now - $0.seen > 1.2 || distance(from: mouse, to: $0.frame) > reach * 2 }
        expandedRows.removeAll { now - $0.at >= 1 }
        for _ in 0..<probes {
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let radius = reach * CGFloat.random(in: 0.01...1).squareRoot()
            let p = CGPoint(x: mouse.x + cos(angle) * radius, y: mouse.y + sin(angle) * radius)
            var hit: AXUIElement?
            guard AXUIElementCopyElementAtPosition(system, Float(p.x), Float(flip - p.y), &hit) == .success,
                  let hit else { continue }
            for frame in strikable(hit, flip: flip, now: now) { remember(frame, now: now) }
        }
        return found.map(\.frame)
    }

    private func remember(_ frame: CGRect, now: CFTimeInterval) {
        if let i = found.firstIndex(where: { $0.frame == frame }) {
            found[i].seen = now
        } else {
            found.append((frame, now))
        }
    }

    /// The button or icon at a hit spot: the element itself, or the closest parent that is one.
    private func strikable(_ hit: AXUIElement, flip: CGFloat, now: CFTimeInterval) -> [CGRect] {
        var element = hit
        for depth in 0..<3 {
            let (role, frame) = info(element, flip: flip)
            if Self.roles.contains(role) { return frame.flatMap { usable($0) ? [$0] : nil } ?? [] }
            if depth == 0, Self.rows.contains(role), let frame, !expandedRows.contains(where: { $0.frame == frame }) {
                expandedRows.append((frame, now))
                return children(of: element).prefix(40).compactMap { child in
                    let (role, frame) = info(child, flip: flip)
                    guard Self.roles.contains(role), let frame, usable(frame) else { return nil }
                    return frame
                }
            }
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parent) == .success,
                  let parent, CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
            element = parent as! AXUIElement
        }
        return []
    }

    /// Small enough to look like a button or icon rather than a whole panel.
    private func usable(_ r: CGRect) -> Bool {
        r.width >= 6 && r.height >= 6 && max(r.width, r.height) <= 320 && r.width * r.height <= 20_000
    }

    /// Role and frame in one round trip to the app.
    private func info(_ e: AXUIElement, flip: CGFloat) -> (role: String, frame: CGRect?) {
        let names = [kAXRoleAttribute, kAXPositionAttribute, kAXSizeAttribute] as CFArray
        var values: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(e, names, AXCopyMultipleAttributeOptions(rawValue: 0), &values) == .success,
              let list = values as? [AnyObject], list.count == 3 else { return ("", nil) }
        let role = list[0] as? String ?? ""
        var origin = CGPoint.zero, size = CGSize.zero
        guard CFGetTypeID(list[1]) == AXValueGetTypeID(), CFGetTypeID(list[2]) == AXValueGetTypeID(),
              AXValueGetValue(list[1] as! AXValue, .cgPoint, &origin),
              AXValueGetValue(list[2] as! AXValue, .cgSize, &size) else { return (role, nil) }
        return (role, CGRect(x: origin.x, y: flip - origin.y - size.height, width: size.width, height: size.height))
    }

    private func children(of e: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, kAXChildrenAttribute as CFString, &value) == .success,
              let list = value as? [AnyObject] else { return [] }
        return list.compactMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil }
    }

    private func distance(from p: CGPoint, to r: CGRect) -> CGFloat {
        hypot(max(r.minX - p.x, 0, p.x - r.maxX), max(r.minY - p.y, 0, p.y - r.maxY))
    }
}

// MARK: - Keeping targets fresh

/// Looks for targets around the pointer on a background queue while the mouse moves, so the 120 fps drawing
/// never waits on it: window edges about 20 times a second, and buttons and icons every other time, since asking
/// other apps about them is slower. Use from the main thread.
final class TargetFinder {
    private(set) var targets = Targets()
    private(set) var scannedAt: CFTimeInterval = -.infinity
    /// Also look for buttons and icons. Only set this once Accessibility is allowed.
    var findsElements = false

    private var busy = false
    private var startedAt: CFTimeInterval = -.infinity
    private var scans = 0
    private let queue = DispatchQueue(label: "dev.lighttrail.targets", qos: .userInitiated)
    private let probe = ElementProbe()

    /// Targets from a scan this recent; nothing if the last scan is too old to trust.
    func fresh(now: CFTimeInterval) -> Targets {
        now - scannedAt < 0.3 ? targets : Targets()
    }

    func update(mouse: CGPoint, now: CFTimeInterval) {
        guard !busy, now - startedAt >= 1.0 / 20 else { return }
        busy = true
        startedAt = now
        let screens = NSScreen.screens.map(\.frame)
        let flip = NSScreen.screens.first?.frame.height ?? 0
        scans += 1
        let elements = findsElements
        let previous = fresh(now: now).elements
        // Probe every other scan, and always when there's nothing recent to reuse.
        let probing = scans % 2 == 0 || previous.isEmpty
        queue.async { [self] in
            let edges = WindowEdges.onScreen(screens: screens, flip: flip)
            let found = !elements ? [] :
                probing ? probe.scan(around: mouse, reach: Config.strikeReach * 1.3, flip: flip, now: now) : previous
            DispatchQueue.main.async {
                self.targets = Targets(edges: edges, elements: found)
                self.scannedAt = CACurrentMediaTime()
                self.busy = false
            }
        }
    }

    /// `--targets`: print what lightning could strike around the pointer (or around `at`) right now.
    static func printTargets(at point: CGPoint? = nil) {
        let screens = NSScreen.screens.map(\.frame)
        let flip = NSScreen.screens.first?.frame.height ?? 0
        let mouse = point ?? NSEvent.mouseLocation
        let edges = WindowEdges.onScreen(screens: screens, flip: flip)
        print("Looking around \(Int(mouse.x)), \(Int(mouse.y)). \(edges.count) visible window edges on screen:")
        for e in edges { print("  (\(Int(e.a.x)), \(Int(e.a.y))) to (\(Int(e.b.x)), \(Int(e.b.y)))") }
        guard AXIsProcessTrusted() else {
            print("Accessibility isn't allowed for this process, so no buttons or icons.")
            return
        }
        let probe = ElementProbe()
        var found: [CGRect] = []
        let start = CACurrentMediaTime()
        for _ in 0..<15 { found = probe.scan(around: mouse, reach: Config.strikeReach * 1.3, flip: flip, now: CACurrentMediaTime()) }
        let ms = Int((CACurrentMediaTime() - start) * 1000 / 15)
        print("\(found.count) buttons and icons nearby (about \(ms) ms per scan):")
        for r in found { print("  \(Int(r.width))×\(Int(r.height)) at (\(Int(r.minX)), \(Int(r.minY)))") }
    }
}
