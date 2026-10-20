import CoreGraphics
import Foundation

// MARK: - Simulation

struct TrailPoint {
    var p: CGPoint
    var t: CFTimeInterval
    var energy: CGFloat   // 0...1, based on speed when the point was laid down
}

struct Bolt {
    var paths: [[CGPoint]]
    var widths: [CGFloat]
    var born: CFTimeInterval
    var life: CFTimeInterval
}

struct Spark {
    var p: CGPoint
    var v: CGVector
    var born: CFTimeInterval
    var life: CFTimeInterval
}

/// A bolt that jumps from the pointer to something on screen and stays attached to the pointer while it lives.
struct Strike {
    enum Aim {
        /// Slides along a window edge to stay closest to the pointer, `slide` points to one side.
        case edge(Edge, slide: CGFloat)
        /// A fixed spot on a button or icon.
        case element(CGRect, spot: CGPoint)
    }

    var aim: Aim
    var born: CFTimeInterval
    var life: CFTimeInterval
    var thick: CGFloat
    /// The bolt keeps its shape while the pointer drags it around, and takes a new shape now and then.
    var seed: UInt64
    var reshapeAt: CFTimeInterval
    var end: CGPoint
    var paths: [[CGPoint]] = []
    var widths: [CGFloat] = []
    /// Electricity running along the struck window edge.
    var crawl: [CGPoint] = []
}

/// Midpoint-displacement lightning between two points.
func jagged(from a: CGPoint, to b: CGPoint, roughness: CGFloat, depth: Int) -> [CGPoint] {
    jagged(from: a, to: b, roughness: roughness, depth: depth, using: &rng)
}

func jagged<G: RandomNumberGenerator>(from a: CGPoint, to b: CGPoint, roughness: CGFloat, depth: Int,
                                      using g: inout G) -> [CGPoint] {
    var pts = [a, b]
    var disp = roughness
    for _ in 0..<depth {
        var next: [CGPoint] = [pts[0]]
        for i in 1..<pts.count {
            let p0 = pts[i - 1], p1 = pts[i]
            let dx = p1.x - p0.x, dy = p1.y - p0.y
            let len = max(hypot(dx, dy), 0.001)
            let off = CGFloat.random(in: -disp...disp, using: &g)
            next.append(CGPoint(x: (p0.x + p1.x) / 2 - dy / len * off,
                                y: (p0.y + p1.y) / 2 + dx / len * off))
            next.append(p1)
        }
        pts = next
        disp *= 0.55
    }
    return pts
}

/// The trail, bolts, strikes and sparks. Fed a pointer position and a time every frame;
/// it doesn't know where they come from (the real mouse, or a scripted path for the README).
final class Engine {
    var trail: [TrailPoint] = []
    var bolts: [Bolt] = []
    var strikes: [Strike] = []
    var sparks: [Spark] = []
    var flash: (p: CGPoint, born: CFTimeInterval)?
    var theme: Theme = .red
    /// The glowing trail with its bolts and sparks.
    var trailOn = true
    /// Lightning jumping from the pointer to nearby `targets`.
    var strikesOn = false
    var targets = Targets()
    private(set) var now: CFTimeInterval = 0
    private(set) var mouse: CGPoint = .zero
    private var smoothedEnergy: CGFloat = 0

    func reset(mouse m: CGPoint, time: CFTimeInterval) {
        mouse = m
        now = time
    }

    func clear() {
        trail = []
        bolts = []
        strikes = []
        sparks = []
        flash = nil
    }

    func step(mouse m: CGPoint, time: CFTimeInterval) {
        let prevTime = now
        now = time
        let dt = max(now - prevTime, 1.0 / 240)

        let dx = m.x - mouse.x, dy = m.y - mouse.y
        let dist = hypot(dx, dy)
        let speed = dist / CGFloat(dt)
        let energy = min(1, speed / Config.speedForMaxEnergy)
        smoothedEnergy += (energy - smoothedEnergy) * 0.35

        let moving = dist > 0.5 && dist < 3000
        if moving && trailOn {
            // Fill in big jumps so fast flicks stay continuous.
            let steps = max(1, Int(dist / 7))
            for i in 1...steps {
                let f = CGFloat(i) / CGFloat(steps)
                trail.append(TrailPoint(p: CGPoint(x: mouse.x + dx * f, y: mouse.y + dy * f),
                                        t: prevTime + dt * Double(f),
                                        energy: max(0.25, smoothedEnergy)))
            }
            spawnEffects(at: m, angle: atan2(dy, dx), energy: smoothedEnergy, dt: dt)
        }
        if moving && strikesOn { spawnStrike(from: m, energy: smoothedEnergy, dt: dt) }
        mouse = m

        // Age everything out.
        trail.removeAll { now - $0.t > Config.trailLife }
        if trail.count > Config.maxTrailPoints { trail.removeFirst(trail.count - Config.maxTrailPoints) }
        bolts.removeAll { now - $0.born > $0.life }
        strikes.removeAll { now - $0.born > $0.life }
        sparks.removeAll { now - $0.born > $0.life }
        if let f = flash, now - f.born > 0.18 { flash = nil }

        let drag = CGFloat(pow(0.03, dt))
        for i in sparks.indices {
            sparks[i].p.x += sparks[i].v.dx * CGFloat(dt)
            sparks[i].p.y += sparks[i].v.dy * CGFloat(dt)
            sparks[i].v.dx *= drag
            sparks[i].v.dy = sparks[i].v.dy * drag - 300 * CGFloat(dt)   // a little gravity
        }
        for i in strikes.indices { follow(&strikes[i]) }
    }

    // MARK: Strikes

    /// Every frame the pointer moves there's a chance lightning jumps to something nearby.
    /// Faster movement means more strikes at once, reaching further; closer targets get struck more often.
    private func spawnStrike(from p: CGPoint, energy: CGFloat, dt: CFTimeInterval) {
        let frameScale = CGFloat(dt * 120)
        let allowed = min(Config.maxStrikes, 3 + Int(energy * CGFloat(Config.maxStrikes - 2)))
        guard strikes.count < allowed, chance((0.16 + 0.6 * energy) * frameScale) else { return }

        let reach = Config.strikeReach * (0.75 + 0.5 * energy)
        var options: [(aim: Strike.Aim, end: CGPoint, weight: CGFloat)] = []
        func consider(_ aim: Strike.Aim, end: CGPoint, bonus: CGFloat) {
            let d = hypot(end.x - p.x, end.y - p.y)
            guard d > 18, d < reach else { return }
            // Spread out: don't hit a spot that's already being struck.
            guard !strikes.contains(where: { hypot($0.end.x - end.x, $0.end.y - end.y) < 26 }) else { return }
            let closeness = 1 - d / reach
            options.append((aim, end, (closeness * closeness + 0.04) * bonus))
        }
        for edge in targets.edges {
            let slide = rand(-40...40)
            consider(.edge(edge, slide: slide), end: edge.point(near: p, slide: slide), bonus: 1)
        }
        for r in targets.elements where !r.insetBy(dx: -4, dy: -4).contains(p) {
            let spot = CGPoint(x: r.midX + r.width * rand(-0.2...0.2), y: r.midY + r.height * rand(-0.2...0.2))
            consider(.element(r, spot: spot), end: spot, bonus: 1.6)
        }
        guard !options.isEmpty else { return }

        var pick = rand(0...options.reduce(0) { $0 + $1.weight })
        var chosen = options[options.count - 1]
        for o in options {
            pick -= o.weight
            if pick <= 0 { chosen = o; break }
        }

        let strike = Strike(aim: chosen.aim, born: now, life: Double(rand(Config.strikeLife) * (1 + 0.3 * energy)),
                            thick: (0.8 + 0.6 * energy) * rand(0.85...1.15), seed: rng.next(), reshapeAt: now,
                            end: chosen.end)
        strikes.append(strike)   // shaped at the end of this frame's step, from where the pointer ends up

        // A few sparks fly off where it lands.
        let back = atan2(p.y - chosen.end.y, p.x - chosen.end.x)
        for _ in 0..<randInt(2...5) {
            let a = back + rand(-1.3...1.3)
            let s = rand(60...260) * (0.6 + energy)
            sparks.append(Spark(p: chosen.end, v: CGVector(dx: cos(a) * s, dy: sin(a) * s),
                                born: now, life: Double(rand(Config.sparkLife))))
        }
    }

    /// Re-draws a strike from where the pointer is now to its target.
    private func follow(_ s: inout Strike) {
        switch s.aim {
        case let .edge(edge, slide): s.end = edge.point(near: mouse, slide: slide)
        case let .element(_, spot): s.end = spot
        }
        let len = hypot(s.end.x - mouse.x, s.end.y - mouse.y)
        // Pull far enough away and the arc snaps.
        if len > Config.strikeReach * 1.6 { s.life = min(s.life, now - s.born + 0.03) }
        if now >= s.reshapeAt {
            s.seed = rng.next()
            s.reshapeAt = now + Double(rand(0.03...0.07))
        }

        var g = SplitMix64(state: s.seed)
        func r(_ range: ClosedRange<CGFloat>) -> CGFloat { CGFloat.random(in: range, using: &g) }
        let main = jagged(from: mouse, to: s.end, roughness: len * 0.28, depth: 5, using: &g)
        s.paths = [main]
        s.widths = [1.8 * s.thick]
        // Forks near the far end, as if the charge spreads out when it lands.
        let angle = atan2(s.end.y - mouse.y, s.end.x - mouse.x)
        for _ in 0..<Int(r(0...2.6)) {
            let start = main[Int(r(0.4...0.85) * CGFloat(main.count - 1))]
            let a = angle + (r(0...1) < 0.5 ? 1 : -1) * r(0.4...1.1)
            let l = len * r(0.12...0.32)
            let tip = CGPoint(x: start.x + cos(a) * l, y: start.y + sin(a) * l)
            s.paths.append(jagged(from: start, to: tip, roughness: l * 0.3, depth: 4, using: &g))
            s.widths.append(0.8 * s.thick)
        }
        if case let .edge(edge, _) = s.aim {
            let d = edge.direction
            let back = r(12...50) * s.thick, ahead = r(12...50) * s.thick
            let from = edge.point(near: CGPoint(x: s.end.x - d.dx * back, y: s.end.y - d.dy * back))
            let to = edge.point(near: CGPoint(x: s.end.x + d.dx * ahead, y: s.end.y + d.dy * ahead))
            s.crawl = jagged(from: from, to: to, roughness: 6, depth: 4, using: &g)
        }
    }

    private func spawnEffects(at p: CGPoint, angle: CGFloat, energy: CGFloat, dt: CFTimeInterval) {
        let frameScale = CGFloat(dt * 120)   // keep rates stable regardless of frame rate

        // Forked bolts tearing off the cursor.
        if energy > 0.08 && chance(energy * 0.8 * frameScale) {
            let a = angle + .pi + rand(-1.9...1.9)
            spawnBolt(from: p, angle: a, length: rand(50...150) * (0.5 + energy), branches: randInt(1...2))
        }

        // Big thunder strike on very fast flicks.
        if energy > 0.85 && chance(0.06 * frameScale) {
            spawnBolt(from: p, angle: angle + .pi + rand(-1.2...1.2), length: rand(160...280), branches: 3, thick: 1.7)
            flash = (p, now)
        }

        // Small crackles along the young part of the trail.
        if trail.count > 8 && chance(energy * 0.6 * frameScale) {
            let idx = randInt((trail.count / 2)..<trail.count)
            spawnBolt(from: trail[idx].p, angle: rand(0...(2 * .pi)), length: rand(14...45), branches: 0, thick: 0.7)
        }

        // Sparks.
        let count = Int(energy * 3 * frameScale + rand(0...0.8))
        for _ in 0..<count {
            let a = angle + .pi + rand(-1.2...1.2)
            let s = rand(80...420) * (0.4 + energy)
            sparks.append(Spark(p: p, v: CGVector(dx: cos(a) * s, dy: sin(a) * s),
                                born: now, life: Double(rand(Config.sparkLife))))
        }
    }

    private func spawnBolt(from p: CGPoint, angle: CGFloat, length: CGFloat, branches: Int, thick: CGFloat = 1) {
        let end = CGPoint(x: p.x + cos(angle) * length, y: p.y + sin(angle) * length)
        let main = jagged(from: p, to: end, roughness: length * 0.3, depth: 5)
        var paths = [main]
        var widths: [CGFloat] = [1.6 * thick]
        for _ in 0..<branches {
            let start = main[randInt((main.count / 5)..<(main.count * 4 / 5))]
            let ba = angle + (chance(0.5) ? 1 : -1) * rand(0.3...0.9)
            let bl = length * rand(0.3...0.6)
            let bEnd = CGPoint(x: start.x + cos(ba) * bl, y: start.y + sin(ba) * bl)
            paths.append(jagged(from: start, to: bEnd, roughness: bl * 0.3, depth: 4))
            widths.append(0.9 * thick)
        }
        bolts.append(Bolt(paths: paths, widths: widths, born: now, life: Double(rand(Config.boltLife))))
    }

    /// Rect containing everything currently drawn, glow included.
    func bounds() -> CGRect {
        var minX = CGFloat.infinity, minY = CGFloat.infinity, maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
        func add(_ p: CGPoint) {
            minX = min(minX, p.x); minY = min(minY, p.y); maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
        trail.forEach { add($0.p) }
        bolts.forEach { $0.paths.forEach { $0.forEach(add) } }
        for s in strikes {
            s.paths.forEach { $0.forEach(add) }
            s.crawl.forEach(add)
            if case let .element(r, _) = s.aim { add(r.origin); add(CGPoint(x: r.maxX, y: r.maxY)) }
        }
        sparks.forEach { add($0.p) }
        if let f = flash { add(f.p) }
        guard minX.isFinite else { return .null }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).insetBy(dx: -90, dy: -90)
    }
}
