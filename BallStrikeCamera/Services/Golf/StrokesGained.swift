import Foundation

// MARK: - Strokes Gained Scaffolding
//
// Architecture-only foundation. NOT a PGA-grade implementation. The public API is shaped
// so a real baseline table (Mark Broadie style) or per-user baseline can drop in later
// without touching call-sites.
//
// Conceptual flow:
//   let baseline   = ExpectedStrokesProvider.default
//   let beforeXS   = baseline.expected(distanceYds: 380, lie: .tee)
//   let afterXS    = baseline.expected(distanceYds: 150, lie: .fairway)
//   let sg         = StrokesGainedEngine.compute(before: beforeXS, after: afterXS, penalty: 0)

// MARK: - Distance buckets

/// 10-yard buckets ≤ 100 yds, 25-yard buckets up to 300, 50-yard buckets beyond.
/// Stable identifiers used as JSON keys when the future baseline table is published.
struct DistanceBucket: Hashable, Codable {
    let minYds: Int
    let maxYds: Int

    var key: String { "\(minYds)-\(maxYds)" }

    static let allBuckets: [DistanceBucket] = {
        var out: [DistanceBucket] = []
        // 0–100 in 10s
        for s in stride(from: 0, to: 100, by: 10) { out.append(.init(minYds: s, maxYds: s + 10)) }
        // 100–300 in 25s
        for s in stride(from: 100, to: 300, by: 25) { out.append(.init(minYds: s, maxYds: s + 25)) }
        // 300–650 in 50s
        for s in stride(from: 300, to: 650, by: 50) { out.append(.init(minYds: s, maxYds: s + 50)) }
        return out
    }()

    static func bucket(forYards y: Double) -> DistanceBucket {
        let i = Int(y.rounded())
        return allBuckets.first { i >= $0.minYds && i < $0.maxYds } ?? allBuckets.last!
    }
}

// MARK: - Expected strokes provider

/// Source of expected-strokes-to-hole values keyed by (distance bucket, lie). The default
/// instance is a stub returning a smooth analytic approximation. Production replaces this
/// with `BroadieBaselineProvider` once the PGA Tour table is bundled.
protocol ExpectedStrokesProvider {
    func expected(distanceYds: Double, lie: ShotLie) -> Double
}

struct StubExpectedStrokesProvider: ExpectedStrokesProvider {
    func expected(distanceYds yd: Double, lie: ShotLie) -> Double {
        // Loose analytic curve. Useful for placeholder UI; not PGA-grade.
        // Sources roughly mimic Broadie's curves so that the order of magnitude is sensible.
        switch lie {
        case .green, .fringe:
            // Putting: 1 + tiny coefficient on distance
            return 1.0 + min(2.5, yd * 0.02)
        case .tee:
            // From tee, par bias removes after first shot
            return 2.6 + log(max(yd, 1)) * 0.32
        case .fairway:
            return 2.4 + log(max(yd, 1)) * 0.32
        case .rough, .recovery:
            return 2.6 + log(max(yd, 1)) * 0.34
        case .sand:
            return 2.8 + log(max(yd, 1)) * 0.32
        case .water:
            // Water itself has no expected strokes; treat as penalty at this distance.
            return 3.4 + log(max(yd, 1)) * 0.32
        case .unknown:
            return 2.6 + log(max(yd, 1)) * 0.32
        }
    }
}

extension ExpectedStrokesProvider where Self == StubExpectedStrokesProvider {
    static var stub: StubExpectedStrokesProvider { .init() }
}

// MARK: - Engine

enum StrokesGainedEngine {
    /// `sg = beforeXS - afterXS - 1 - penalty`
    /// - beforeXS: expected strokes to hole from where the ball started
    /// - afterXS:  expected strokes to hole from where the ball ended
    /// - penalty:  additional strokes added (e.g., 1 for water)
    static func compute(beforeXS: Double, afterXS: Double, penalty: Double = 0) -> Double {
        beforeXS - afterXS - 1 - penalty
    }

    /// Compute and stamp `expectedStrokes` and `strokesGained` on a single shot, given a
    /// provider and the post-shot "remaining" distance the next stroke faces.
    static func annotate(_ shot: inout TrackedShot,
                          distanceToHoleBefore: Double,
                          distanceToHoleAfter: Double,
                          lieAfter: ShotLie,
                          penalty: Double = 0,
                          provider: ExpectedStrokesProvider = .stub) {
        let before = provider.expected(distanceYds: distanceToHoleBefore, lie: shot.lie)
        let after  = provider.expected(distanceYds: distanceToHoleAfter,  lie: lieAfter)
        shot.expectedStrokes = before
        shot.strokesGained   = compute(beforeXS: before, afterXS: after, penalty: penalty)
    }
}
