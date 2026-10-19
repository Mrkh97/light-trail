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

/// Midpoint-displacement lightning between two points.
func jagged(from a: CGPoint, to b: CGPoint, roughness: CGFloat, depth: Int) -> [CGPoint] {
    var pts = [a, b]
    var disp = roughness
    for _ in 0..<depth {
        var next: [CGPoint] = [pts[0]]
        for i in 1..<pts.count {
            let p0 = pts[i - 1], p1 = pts[i]
            let dx = p1.x - p0.x, dy = p1.y - p0.y
            let len = max(hypot(dx, dy), 0.001)
            let off = rand(-disp...disp)
            next.append(CGPoint(x: (p0.x + p1.x) / 2 - dy / len * off,
                                y: (p0.y + p1.y) / 2 + dx / len * off))
            next.append(p1)
        }
        pts = next
        disp *= 0.55
    }
    return pts
}

/// The trail, bolts and sparks. Fed a pointer position and a time every frame;
/// it doesn't know where they come from (the real mouse, or a scripted path for the README).
final class Engine {
    var trail: [TrailPoint] = []
    var bolts: [Bolt] = []
    var sparks: [Spark] = []
    var flash: (p: CGPoint, born: CFTimeInterval)?
    var theme: Theme = .red
    private(set) var now: CFTimeInterval = 0
    private var lastMouse: CGPoint = .zero
    private var smoothedEnergy: CGFloat = 0

    func reset(mouse: CGPoint, time: CFTimeInterval) {
        lastMouse = mouse
        now = time
    }

    func clear() {
        trail = []
        bolts = []
        sparks = []
        flash = nil
    }

    func step(mouse m: CGPoint, time: CFTimeInterval) {
        let prevTime = now
        now = time
        let dt = max(now - prevTime, 1.0 / 240)

        let dx = m.x - lastMouse.x, dy = m.y - lastMouse.y
        let dist = hypot(dx, dy)
        let speed = dist / CGFloat(dt)
        let energy = min(1, speed / Config.speedForMaxEnergy)
        smoothedEnergy += (energy - smoothedEnergy) * 0.35

        if dist > 0.5 && dist < 3000 {
            // Fill in big jumps so fast flicks stay continuous.
            let steps = max(1, Int(dist / 7))
            for i in 1...steps {
                let f = CGFloat(i) / CGFloat(steps)
                trail.append(TrailPoint(p: CGPoint(x: lastMouse.x + dx * f, y: lastMouse.y + dy * f),
                                        t: prevTime + dt * Double(f),
                                        energy: max(0.25, smoothedEnergy)))
            }
            spawnEffects(at: m, angle: atan2(dy, dx), energy: smoothedEnergy, dt: dt)
        }
        lastMouse = m

        // Age everything out.
        trail.removeAll { now - $0.t > Config.trailLife }
        if trail.count > Config.maxTrailPoints { trail.removeFirst(trail.count - Config.maxTrailPoints) }
        bolts.removeAll { now - $0.born > $0.life }
        sparks.removeAll { now - $0.born > $0.life }
        if let f = flash, now - f.born > 0.18 { flash = nil }

        let drag = CGFloat(pow(0.03, dt))
        for i in sparks.indices {
            sparks[i].p.x += sparks[i].v.dx * CGFloat(dt)
            sparks[i].p.y += sparks[i].v.dy * CGFloat(dt)
            sparks[i].v.dx *= drag
            sparks[i].v.dy = sparks[i].v.dy * drag - 300 * CGFloat(dt)   // a little gravity
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
        sparks.forEach { add($0.p) }
        if let f = flash { add(f.p) }
        guard minX.isFinite else { return .null }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).insetBy(dx: -90, dy: -90)
    }
}
