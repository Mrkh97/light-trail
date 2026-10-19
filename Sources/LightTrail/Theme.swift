import AppKit

struct RGB {
    var r, g, b: CGFloat
    init(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) { self.r = r; self.g = g; self.b = b }

    /// Blend toward white — the hot center of the energy.
    func mixed(white w: CGFloat) -> RGB { RGB(r + (1 - r) * w, g + (1 - g) * w, b + (1 - b) * w) }
    func cg(_ a: CGFloat) -> CGColor { rgba(r, g, b, a) }
    var ns: NSColor { NSColor(red: r, green: g, blue: b, alpha: 1) }
}

/// The color of the energy. Every shade (outer glow, core, bolts, sparks) is mixed from one base color.
enum Theme: String, CaseIterable {
    case red, blue, purple, green, gold, cyan, pink, ice, rainbow

    var title: String {
        switch self {
        case .red: "Red"
        case .blue: "Blue"
        case .purple: "Purple"
        case .green: "Toxic Green"
        case .gold: "Gold"
        case .cyan: "Cyan"
        case .pink: "Pink"
        case .ice: "Ice White"
        case .rainbow: "Rainbow"
        }
    }

    /// Base color of the energy. Rainbow shifts hue over time, so the trail becomes a gradient.
    func base(at t: CFTimeInterval) -> RGB {
        switch self {
        case .red: RGB(1, 0.06, 0.03)
        case .blue: RGB(0.08, 0.25, 1)
        case .purple: RGB(0.6, 0.1, 1)
        case .green: RGB(0.2, 1, 0.1)
        case .gold: RGB(1, 0.55, 0.03)
        case .cyan: RGB(0.03, 0.8, 1)
        case .pink: RGB(1, 0.1, 0.55)
        case .ice: RGB(0.6, 0.78, 1)
        case .rainbow: Theme.hue(CGFloat((t * 1.1).truncatingRemainder(dividingBy: 1)))
        }
    }

    static func hue(_ h: CGFloat) -> RGB {
        let c = NSColor(calibratedHue: h, saturation: 0.95, brightness: 1, alpha: 1)
        return RGB(c.redComponent, c.greenComponent, c.blueComponent)
    }
}
