import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Paints the app icon and the README pictures with the real engine and renderer,
/// driven by a scripted pointer instead of the mouse. See docs/make-visuals.sh.
enum Showcase {
    // MARK: Icon

    static func renderIcon(to path: String) {
        rng = SplitMix64(state: 7)
        let ctx = makeContext(width: 1024, height: 1024)
        let body = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824),
                          cornerWidth: 185, cornerHeight: 185, transform: nil)

        // Dark tile with a soft drop shadow.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: rgba(0, 0, 0, 0.45))
        ctx.addPath(body)
        ctx.setFillColor(rgba(0.05, 0.01, 0.02, 1))
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(body)
        ctx.clip()
        linearGradient(ctx, from: rgba(0.17, 0.03, 0.05, 1), to: rgba(0.03, 0.005, 0.01, 1),
                       start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100))
        radialGlow(ctx, at: CGPoint(x: 520, y: 500), radius: 440, color: rgba(1, 0.05, 0.02, 0.45))

        // Crackles leaping off the bolt.
        let red = Theme.red.base(at: 0)
        ctx.setBlendMode(.plusLighter)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setShadow(offset: .zero, blur: 30, color: red.cg(1))
        let arcs: [(CGPoint, CGPoint)] = [
            (CGPoint(x: 715, y: 600), CGPoint(x: 880, y: 470)),
            (CGPoint(x: 335, y: 452), CGPoint(x: 150, y: 560)),
            (CGPoint(x: 690, y: 880), CGPoint(x: 850, y: 960)),
            (CGPoint(x: 405, y: 140), CGPoint(x: 250, y: 60)),
        ]
        for (a, b) in arcs {
            let path = CGMutablePath()
            path.addLines(between: jagged(from: a, to: b, roughness: 70, depth: 6))
            for (w, white, alpha) in [(14.0, 0.05, 0.55), (4.5, 0.8, 0.95)] as [(CGFloat, CGFloat, CGFloat)] {
                ctx.addPath(path)
                ctx.setLineWidth(w)
                ctx.setStrokeColor(red.mixed(white: white).cg(alpha))
                ctx.strokePath()
            }
        }

        // The bolt: red bloom, then a white-hot to red fill.
        let bolt = CGMutablePath()
        bolt.addLines(between: [
            CGPoint(x: 545, y: 885), CGPoint(x: 690, y: 885), CGPoint(x: 590, y: 600), CGPoint(x: 720, y: 600),
            CGPoint(x: 400, y: 135), CGPoint(x: 480, y: 450), CGPoint(x: 330, y: 450),
        ])
        bolt.closeSubpath()
        ctx.setBlendMode(.normal)
        ctx.setShadow(offset: .zero, blur: 90, color: red.cg(1))
        ctx.addPath(bolt)
        ctx.setFillColor(red.cg(1))
        ctx.fillPath()
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        ctx.addPath(bolt)
        ctx.clip()
        linearGradient(ctx, from: red.mixed(white: 0.9).cg(1), to: red.mixed(white: 0.15).cg(1),
                       start: CGPoint(x: 600, y: 885), end: CGPoint(x: 420, y: 135))
        ctx.restoreGState()

        savePNG(ctx, to: path)
    }

    // MARK: Color sheet

    static func renderColors(to path: String) {
        let cols = 3, tileW: CGFloat = 400, tileH: CGFloat = 220, gap: CGFloat = 12
        let themes = Theme.allCases
        let rows = (themes.count + cols - 1) / cols
        let width = CGFloat(cols) * tileW + CGFloat(cols - 1) * gap
        let height = CGFloat(rows) * tileH + CGFloat(rows - 1) * gap
        let ctx = makeContext(width: width, height: height)

        for (i, theme) in themes.enumerated() {
            let col = i % cols, row = i / cols
            let tile = CGRect(x: CGFloat(col) * (tileW + gap), y: height - CGFloat(row + 1) * tileH - CGFloat(row) * gap,
                              width: tileW, height: tileH)
            ctx.saveGState()
            ctx.addPath(CGPath(roundedRect: tile, cornerWidth: 16, cornerHeight: 16, transform: nil))
            ctx.clip()
            backdrop(ctx, in: tile)

            // A quick wavy swipe from left to right, captured as it ends.
            rng = SplitMix64(state: 11)
            let engine = Engine()
            engine.theme = theme
            let duration = 0.45
            let mid = tile.midY + 4
            func pointer(_ t: Double) -> CGPoint {
                let f = CGFloat(t / duration)
                return CGPoint(x: tile.minX + 45 + 300 * f, y: mid + 45 * sin(f * 3 * .pi))
            }
            engine.reset(mouse: pointer(0), time: 0)
            var t = 0.0
            while t < duration {
                t += 1 / Config.fps
                engine.step(mouse: pointer(t), time: t)
            }
            Renderer.draw(engine, in: ctx)
            ctx.setBlendMode(.normal)
            drawCursor(at: pointer(t), in: ctx)
            drawText(theme.title, at: CGPoint(x: tile.midX, y: tile.minY + 16), size: 17, alpha: 0.85, centered: true, in: ctx)
            ctx.restoreGState()
        }
        savePNG(ctx, to: path)
    }

    // MARK: Demo animation

    /// Writes frame_0000.png… at 30 fps: a figure-eight swipe in each color, pausing so the trail can fade.
    /// The pointer ends exactly where it starts, so the GIF loops seamlessly.
    static func renderDemo(toDirectory dir: String) {
        rng = SplitMix64(state: 3)
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let width: CGFloat = 800, height: CGFloat = 450
        let themes: [Theme] = [.red, .blue, .purple, .green, .rainbow]
        let move = 1.35, still = 0.6, cycle = move + still
        let peakRate = Double.pi * Double.pi / move   // one full figure eight (2π) per swipe
        let stepsPerFrame = 4                          // simulate at 120 Hz, keep every 4th frame
        let totalSteps = Int((cycle * Double(themes.count) * Config.fps).rounded())

        func pointer(_ u: Double) -> CGPoint {
            CGPoint(x: width / 2 + 300 * sin(u), y: height / 2 + 130 * sin(2 * u))
        }

        let engine = Engine()
        var u = 0.0
        engine.reset(mouse: pointer(u), time: 0)
        var frame = 0
        for step in 1...totalSteps {
            let t = Double(step) / Config.fps
            let k = min(Int(t / cycle), themes.count - 1)
            let tau = t - Double(k) * cycle
            engine.theme = themes[k]
            if tau < move { u += peakRate * sin(.pi * tau / move) / Config.fps }
            engine.step(mouse: pointer(u), time: t)

            guard step % stepsPerFrame == 0 else { continue }
            let ctx = makeContext(width: width, height: height)
            let canvas = CGRect(x: 0, y: 0, width: width, height: height)
            backdrop(ctx, in: canvas)
            Renderer.draw(engine, in: ctx)
            ctx.setBlendMode(.normal)
            drawCursor(at: pointer(u), in: ctx)
            drawText(themes[k].title, at: CGPoint(x: 22, y: 18), size: 15, alpha: 0.55, centered: false, in: ctx)
            savePNG(ctx, to: "\(dir)/frame_\(String(format: "%04d", frame)).png")
            frame += 1
        }
    }

    // MARK: Helpers

    static func makeContext(width: CGFloat, height: CGFloat) -> CGContext {
        CGContext(data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }

    static func savePNG(_ ctx: CGContext, to path: String) {
        guard let image = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL,
                                                         UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }

    /// A dark, slightly vignetted stand-in for a desktop.
    static func backdrop(_ ctx: CGContext, in rect: CGRect) {
        ctx.saveGState()
        ctx.clip(to: rect)
        linearGradient(ctx, from: rgba(0.09, 0.09, 0.11, 1), to: rgba(0.025, 0.025, 0.035, 1),
                       start: CGPoint(x: rect.midX, y: rect.maxY), end: CGPoint(x: rect.midX, y: rect.minY))
        ctx.restoreGState()
    }

    static func linearGradient(_ ctx: CGContext, from a: CGColor, to b: CGColor, start: CGPoint, end: CGPoint) {
        guard let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [a, b] as CFArray,
                                 locations: [0, 1]) else { return }
        ctx.drawLinearGradient(g, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    static func radialGlow(_ ctx: CGContext, at p: CGPoint, radius: CGFloat, color: CGColor) {
        guard let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                 colors: [color, color.copy(alpha: 0)!] as CFArray, locations: [0, 1]) else { return }
        ctx.drawRadialGradient(g, startCenter: p, startRadius: 0, endCenter: p, endRadius: radius, options: [])
    }

    /// The standard arrow pointer, tip at `p`.
    static func drawCursor(at p: CGPoint, in ctx: CGContext) {
        let s: CGFloat = 1.3
        let shape: [CGPoint] = [(0, 0), (0, 17), (4, 13), (7, 20), (9.5, 19), (6.5, 12), (12, 12)]
            .map { CGPoint(x: p.x + $0.0 * s, y: p.y - $0.1 * s) }
        let path = CGMutablePath()
        path.addLines(between: shape)
        path.closeSubpath()
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -1.5), blur: 3, color: rgba(0, 0, 0, 0.5))
        ctx.addPath(path)
        ctx.setFillColor(rgba(1, 1, 1, 1))
        ctx.fillPath()
        ctx.restoreGState()
        ctx.addPath(path)
        ctx.setStrokeColor(rgba(0, 0, 0, 1))
        ctx.setLineWidth(1.1)
        ctx.setLineJoin(.round)
        ctx.strokePath()
    }

    static func drawText(_ s: String, at p: CGPoint, size: CGFloat, alpha: CGFloat, centered: Bool, in ctx: CGContext) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        let text = NSAttributedString(string: s, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: .semibold),
            .foregroundColor: NSColor(white: 1, alpha: alpha),
        ])
        text.draw(at: CGPoint(x: centered ? p.x - text.size().width / 2 : p.x, y: p.y))
        NSGraphicsContext.restoreGraphicsState()
    }
}
