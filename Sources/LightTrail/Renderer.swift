import AppKit

/// Draws the whole effect into any CGContext, in the engine's coordinate space.
/// The app draws into one transparent window per screen; the showcase draws into bitmaps.
enum Renderer {
    static func draw(_ e: Engine, in ctx: CGContext) {
        ctx.setBlendMode(.plusLighter)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        if let f = e.flash { drawFlash(f.p, age: e.now - f.born, color: e.theme.base(at: f.born), in: ctx) }
        drawImpacts(e, in: ctx)

        // Soft outer glow (cheap wide strokes).
        strokeTrail(e, in: ctx, width: 40, white: 0, alpha: 0.09)
        strokeTrail(e, in: ctx, width: 18, white: 0.03, alpha: 0.2)

        // Everything bright goes into one shadowed group, so it gets a single colored bloom.
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 28, color: e.theme.base(at: e.now).cg(1))
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.setBlendMode(.plusLighter)

        strokeTrail(e, in: ctx, width: Config.trailWidth, white: 0.1, alpha: 0.85)
        strokeTrail(e, in: ctx, width: Config.trailWidth * 0.3, white: 0.8, alpha: 0.9)
        drawArcs(e, in: ctx)
        drawBolts(e, in: ctx)
        drawStrikes(e, in: ctx)
        drawSparks(e, in: ctx)

        ctx.endTransparencyLayer()
        ctx.restoreGState()

        drawHead(e, in: ctx)
        drawSource(e, in: ctx)
    }

    private static func life(_ t: CFTimeInterval, _ e: Engine) -> CGFloat {
        max(0, 1 - CGFloat((e.now - t) / Config.trailLife))
    }

    private static func strokeTrail(_ e: Engine, in ctx: CGContext, width: CGFloat,
                                    white: CGFloat, alpha: CGFloat) {
        let pts = e.trail
        guard pts.count > 1 else { return }
        for i in 1..<pts.count {
            let f = life(pts[i].t, e)
            guard f > 0 else { continue }
            let w = width * f * (0.45 + 0.55 * pts[i].energy)
            ctx.setStrokeColor(e.theme.base(at: pts[i].t).mixed(white: white).cg(alpha * f))
            ctx.setLineWidth(max(0.4, w))
            ctx.move(to: pts[i - 1].p)
            ctx.addLine(to: pts[i].p)
            ctx.strokePath()
        }
    }

    /// Electricity crawling along the trail — re-jittered every frame so it flickers.
    private static func drawArcs(_ e: Engine, in ctx: CGContext) {
        let pts = e.trail
        guard pts.count > 3 else { return }
        for _ in 0..<2 {
            var prev: CGPoint?
            for i in stride(from: 0, to: pts.count, by: 2) {
                let f = life(pts[i].t, e)
                let j = i + 1 < pts.count ? i + 1 : i - 1
                let dx = pts[j].p.x - pts[i].p.x, dy = pts[j].p.y - pts[i].p.y
                let len = max(hypot(dx, dy), 0.001)
                let amp = rand(-1...1) * 11 * f * pts[i].energy
                let q = CGPoint(x: pts[i].p.x - dy / len * amp, y: pts[i].p.y + dx / len * amp)
                if let prev, f > 0 {
                    ctx.setStrokeColor(e.theme.base(at: pts[i].t).mixed(white: 0.5).cg(0.75 * f * rand(0.5...1)))
                    ctx.setLineWidth(1.1)
                    ctx.move(to: prev)
                    ctx.addLine(to: q)
                    ctx.strokePath()
                }
                prev = q
            }
        }
    }

    private static func drawBolts(_ e: Engine, in ctx: CGContext) {
        for b in e.bolts {
            let f = max(0, 1 - CGFloat((e.now - b.born) / b.life))
            let flicker = rand(0.45...1)
            let color = e.theme.base(at: b.born)
            for (path, w) in zip(b.paths, b.widths) {
                guard let first = path.first else { continue }
                let cg = CGMutablePath()
                cg.move(to: first)
                path.dropFirst().forEach { cg.addLine(to: $0) }

                ctx.addPath(cg)
                ctx.setStrokeColor(color.mixed(white: 0.05).cg(0.5 * f * flicker))
                ctx.setLineWidth(w * 3.5)
                ctx.strokePath()

                ctx.addPath(cg)
                ctx.setStrokeColor(color.mixed(white: 0.75).cg(0.95 * f * flicker))
                ctx.setLineWidth(w)
                ctx.strokePath()
            }
        }
    }

    /// Strikes stay bright for most of their life, then drop off quickly.
    private static func strength(_ s: Strike, _ e: Engine) -> CGFloat {
        let age = CGFloat((e.now - s.born) / s.life)
        return max(0, 1 - age * age)
    }

    private static func drawStrikes(_ e: Engine, in ctx: CGContext) {
        for s in e.strikes {
            let f = strength(s, e)
            let flicker = rand(0.55...1)
            let color = e.theme.base(at: s.born)
            for (path, w) in zip(s.paths, s.widths) {
                stroke(path, in: ctx, width: w * 4, color: color.mixed(white: 0.05).cg(0.55 * f * flicker))
                stroke(path, in: ctx, width: w, color: color.mixed(white: 0.75).cg(0.95 * f * flicker))
            }
            stroke(s.crawl, in: ctx, width: 3, color: color.mixed(white: 0.05).cg(0.45 * f * flicker))
            stroke(s.crawl, in: ctx, width: 1, color: color.mixed(white: 0.6).cg(0.85 * f * flicker))

            // The struck button or icon lights up around its outline.
            if case let .element(r, _) = s.aim {
                let box = r.insetBy(dx: -2, dy: -2)
                let radius = min(10, min(box.width, box.height) * 0.25)
                let outline = CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil)
                ctx.addPath(outline)
                ctx.setStrokeColor(color.mixed(white: 0.1).cg(0.35 * f))
                ctx.setLineWidth(4)
                ctx.strokePath()
                ctx.addPath(outline)
                ctx.setStrokeColor(color.mixed(white: 0.6).cg(0.8 * f * flicker))
                ctx.setLineWidth(1.2)
                ctx.strokePath()
            }
        }
    }

    private static func stroke(_ path: [CGPoint], in ctx: CGContext, width: CGFloat, color: CGColor) {
        guard path.count > 1 else { return }
        ctx.addLines(between: path)
        ctx.setStrokeColor(color)
        ctx.setLineWidth(width)
        ctx.strokePath()
    }

    /// A soft glow where each strike lands.
    private static func drawImpacts(_ e: Engine, in ctx: CGContext) {
        for s in e.strikes {
            let f = strength(s, e)
            let c = e.theme.base(at: s.born)
            radial(at: s.end, radius: 16 + 12 * s.thick, colors: [c.mixed(white: 0.6).cg(0.45 * f), c.cg(0)], in: ctx)
        }
    }

    /// The pointer glows while it's throwing strikes.
    private static func drawSource(_ e: Engine, in ctx: CGContext) {
        let f = e.strikes.map { strength($0, e) }.max() ?? 0
        guard f > 0 else { return }
        let c = e.theme.base(at: e.now)
        radial(at: e.mouse, radius: 22, colors: [c.mixed(white: 0.7).cg(0.5 * f), c.mixed(white: 0.05).cg(0.2 * f), c.cg(0)],
               locations: [0, 0.4, 1], in: ctx)
    }

    private static func radial(at p: CGPoint, radius: CGFloat, colors: [CGColor], locations: [CGFloat]? = nil,
                               in ctx: CGContext) {
        guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray,
                                 locations: locations) else { return }
        ctx.drawRadialGradient(g, startCenter: p, startRadius: 0, endCenter: p, endRadius: radius, options: [])
    }

    private static func drawSparks(_ e: Engine, in ctx: CGContext) {
        for s in e.sparks {
            let f = max(0, 1 - CGFloat((e.now - s.born) / s.life))
            let r = 0.6 + 1.6 * f
            ctx.setFillColor(e.theme.base(at: s.born).mixed(white: 0.3 + 0.4 * f).cg(f))
            ctx.fillEllipse(in: CGRect(x: s.p.x - r, y: s.p.y - r, width: r * 2, height: r * 2))
        }
    }

    private static func drawHead(_ e: Engine, in ctx: CGContext) {
        guard let head = e.trail.last else { return }
        let f = life(head.t, e)
        guard f > 0 else { return }
        let r = 26 * (0.5 + 0.5 * head.energy) * f
        let c = e.theme.base(at: head.t)
        let colors = [c.mixed(white: 0.7).cg(0.55 * f), c.mixed(white: 0.05).cg(0.25 * f), c.cg(0)] as CFArray
        guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.35, 1]) else { return }
        ctx.drawRadialGradient(g, startCenter: head.p, startRadius: 0, endCenter: head.p, endRadius: r, options: [])
    }

    private static func drawFlash(_ p: CGPoint, age: CFTimeInterval, color: RGB, in ctx: CGContext) {
        let f = max(0, 1 - CGFloat(age / 0.18))
        let colors = [color.mixed(white: 0.2).cg(0.35 * f), color.cg(0)] as CFArray
        guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
        ctx.drawRadialGradient(g, startCenter: p, startRadius: 0, endCenter: p, endRadius: 90, options: [])
    }
}
