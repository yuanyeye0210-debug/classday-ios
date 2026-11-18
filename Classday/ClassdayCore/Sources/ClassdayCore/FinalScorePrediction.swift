import Foundation

public enum PredictionStatus: String, Equatable, Sendable {
    case required, alreadyReached, impossible, missingScores, invalidRule
}

public struct FinalScoreResult: Equatable, Sendable {
    public var status: PredictionStatus
    public var minimum: Double?
    public init(status: PredictionStatus, minimum: Double? = nil) {
        self.status = status
        self.minimum = minimum
    }
}

/// Read-only what-if calculation; never changes scores or assumes missing scores are zero.
public enum FinalScorePrediction {
    public static func evaluate(scheme: GradeScheme, finalComponentID: String, targetPercent: Double) -> FinalScoreResult {
        let invalid = FinalScoreResult(status: .invalidRule)
        let ids = Set(scheme.components.map(\.id))
        guard scheme.scale.isFinite, scheme.scale > 0, targetPercent.isFinite,
              (0...100).contains(targetPercent), ids.contains(finalComponentID),
              ids.count == scheme.components.count, !scheme.branches.isEmpty else { return invalid }
        let target = targetPercent / 100 * scheme.scale
        var best = Double.infinity
        var missing = false
        for branch in scheme.branches {
            guard !branch.isEmpty,
                  branch.allSatisfy({ $0.weight.isFinite && $0.weight >= 0 && ids.contains($0.componentID) }),
                  abs(branch.reduce(0) { $0 + $1.weight } - 1) <= 1e-6 else { return invalid }
            var known = 0.0
            var finalWeight = 0.0
            for term in branch {
                if term.weight == 0 { continue }
                if term.componentID == finalComponentID { finalWeight += term.weight; continue }
                guard let score = scheme.scores[term.componentID] else { missing = true; continue }
                guard score.isFinite, score >= 0, score <= scheme.scale else { return invalid }
                known += term.weight * score
            }
            guard known.isFinite else { return invalid }
            let needed: Double
            if known >= target { needed = 0 }
            else if finalWeight > 0 { needed = (target - known) / finalWeight }
            else { needed = .infinity }
            best = min(best, needed)
        }
        if missing { return FinalScoreResult(status: .missingScores) }
        if best <= 0 { return FinalScoreResult(status: .alreadyReached, minimum: 0) }
        if best > scheme.scale + scheme.scale * 1e-10 { return FinalScoreResult(status: .impossible) }
        return FinalScoreResult(status: .required, minimum: min(best, scheme.scale))
    }
}
