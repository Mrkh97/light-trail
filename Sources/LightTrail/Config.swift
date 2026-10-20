import CoreGraphics
import Foundation

// MARK: - Tuning

enum Config {
    static let fps: Double = 120
    static let trailLife: CFTimeInterval = 0.45          // how long the trail lingers
    static let trailWidth: CGFloat = 9                   // core width at full speed
    static let boltLife: ClosedRange<CGFloat> = 0.07...0.22
    static let sparkLife: ClosedRange<CGFloat> = 0.25...0.6
    static let speedForMaxEnergy: CGFloat = 2600         // px/s that counts as "full power"
    static let maxTrailPoints = 500

    // Lightning strikes (the bolts that jump from the pointer to window edges, buttons and icons)
    static let strikeReach: CGFloat = 230                // how far a strike can jump, at medium speed
    static let strikeLife: ClosedRange<CGFloat> = 0.14...0.32
    static let maxStrikes = 7                            // at once, when moving fast
}

func rgba(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat) -> CGColor {
    CGColor(red: r, green: g, blue: b, alpha: max(0, min(1, a)))
}

// MARK: - Randomness

/// Small seedable generator, so the README pictures come out the same on every run.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

var rng = SplitMix64(state: UInt64(Date().timeIntervalSince1970 * 1000))

func rand(_ r: ClosedRange<CGFloat>) -> CGFloat { CGFloat.random(in: r, using: &rng) }
func randInt(_ r: Range<Int>) -> Int { Int.random(in: r, using: &rng) }
func randInt(_ r: ClosedRange<Int>) -> Int { Int.random(in: r, using: &rng) }
func chance(_ p: CGFloat) -> Bool { rand(0...1) < p }
