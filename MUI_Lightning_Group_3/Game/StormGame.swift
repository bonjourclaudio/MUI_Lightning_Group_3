//
//  StormGame.swift
//  MUI_Lightning_Group_3
//
//  Author: MUI group 3
//

import Foundation
import Observation

enum Charge: String, Sendable {
    case positive, negative

    var symbol: String { self == .positive ? "+" : "−" }
}

/// The "play god" rules.
///
/// A storm only gains energy when positive AND negative charge come together
/// (charge separation needs both). An excess of one kind weakens the storm,
/// so adding the wrong clouds clears the sky again.
@Observable
final class StormGame {
    private(set) var positive = 0
    private(set) var negative = 0

    /// Number of +/− pairs needed before the air breaks down → lightning.
    let pairsNeeded = 4
    /// How strongly every unmatched cloud weakens the storm.
    let imbalancePenalty: Float = 0.75

    enum Result { case stronger, weaker, unchanged }

    /// 0 … 1. At 1 the air can no longer insulate the charge.
    var intensity: Float {
        let pairs = Float(min(positive, negative))
        let excess = Float(abs(positive - negative))
        return max(0, min(1, (pairs - imbalancePenalty * excess) / Float(pairsNeeded)))
    }

    var isReady: Bool { intensity >= 0.999 }

    /// > 0: too much positive, < 0: too much negative.
    var imbalance: Int { positive - negative }

    @discardableResult
    func add(_ charge: Charge) -> Result {
        let before = intensity
        switch charge {
        case .positive: positive += 1
        case .negative: negative += 1
        }
        let after = intensity
        if after > before + 0.001 { return .stronger }
        if after < before - 0.001 { return .weaker }
        return .unchanged
    }

    func reset() {
        positive = 0
        negative = 0
    }
}
