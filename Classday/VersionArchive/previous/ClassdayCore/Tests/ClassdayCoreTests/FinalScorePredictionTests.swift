import XCTest
import ClassdayCore

final class FinalScorePredictionTests: XCTestCase {
    private func scheme(scale: Double = 100, score: Double = 80) -> GradeScheme {
        GradeScheme(scale: scale, components: [GradeComponent(id: "work", name: "平时"), GradeComponent(id: "final", name: "期末")],
                    scores: ["work": score], branches: [[GradeTerm(componentID: "work", weight: 0.4), GradeTerm(componentID: "final", weight: 0.6)]])
    }

    func testPassTargetAndScale() throws {
        let rule = scheme()
        XCTAssertEqual(try XCTUnwrap(FinalScorePrediction.evaluate(scheme: rule, finalComponentID: "final", targetPercent: 60).minimum), 46.6666666667, accuracy: 1e-8)
        XCTAssertEqual(FinalScorePrediction.evaluate(scheme: rule, finalComponentID: "final", targetPercent: 80).minimum, 80)
        XCTAssertEqual(rule.scores, ["work": 80])
        XCTAssertEqual(try XCTUnwrap(FinalScorePrediction.evaluate(scheme: scheme(scale: 20, score: 16), finalComponentID: "final", targetPercent: 60).minimum), 9.3333333333, accuracy: 1e-8)
    }

    func testStatusesAndBestOfBranches() {
        XCTAssertEqual(FinalScorePrediction.evaluate(scheme: scheme(), finalComponentID: "final", targetPercent: 30).status, .alreadyReached)
        XCTAssertEqual(FinalScorePrediction.evaluate(scheme: scheme(), finalComponentID: "final", targetPercent: 100).status, .impossible)
        var rule = scheme()
        rule.branches.append([GradeTerm(componentID: "work", weight: 1)])
        XCTAssertEqual(FinalScorePrediction.evaluate(scheme: rule, finalComponentID: "final", targetPercent: 60).status, .alreadyReached)
        rule.scores = [:]
        XCTAssertEqual(FinalScorePrediction.evaluate(scheme: rule, finalComponentID: "final", targetPercent: 60).status, .missingScores)
    }

    func testInvalidRulesAndFinalScoreIgnored() throws {
        for bad in [Double.nan, Double.infinity, -1, 101] {
            XCTAssertEqual(FinalScorePrediction.evaluate(scheme: scheme(score: bad), finalComponentID: "final", targetPercent: 60).status, .invalidRule)
        }
        var rule = scheme()
        rule.scores["final"] = 1
        XCTAssertEqual(try XCTUnwrap(FinalScorePrediction.evaluate(scheme: rule, finalComponentID: "final", targetPercent: 60).minimum), 46.6666666667, accuracy: 1e-8)
        rule.branches = [[GradeTerm(componentID: "final", weight: 0.5)]]
        XCTAssertEqual(FinalScorePrediction.evaluate(scheme: rule, finalComponentID: "final", targetPercent: 60).status, .invalidRule)
    }

    func testIncompleteAlgorithmBlocksExactMinimum() throws {
        var rule = scheme()
        rule.scores = [:]
        // 第二条算法只用期末分即可算出结果，但第一条算法缺平时成绩时不能给出精确最低分。
        rule.branches = [[GradeTerm(componentID: "work", weight: 0.4), GradeTerm(componentID: "final", weight: 0.6)],
                         [GradeTerm(componentID: "final", weight: 1)]]
        XCTAssertEqual(FinalScorePrediction.evaluate(scheme: rule, finalComponentID: "final", targetPercent: 60).status, .missingScores)
        // 零权重分项不要求录分，也不应把规则误判为缺成绩。
        rule.branches = [[GradeTerm(componentID: "work", weight: 0), GradeTerm(componentID: "final", weight: 1)]]
        XCTAssertEqual(try XCTUnwrap(FinalScorePrediction.evaluate(scheme: rule, finalComponentID: "final", targetPercent: 60).minimum), 60, accuracy: 1e-8)
    }

    func testWeightsMustBeDecimalFractionsNotPercentages() throws {
        // 权重按 0–1 小数录入（每条合计为 1，即 100%）；30/70 这类百分数应按无效规则拒绝。
        var decimal = scheme()
        decimal.branches = [[GradeTerm(componentID: "work", weight: 0.3), GradeTerm(componentID: "final", weight: 0.7)]]
        XCTAssertEqual(try XCTUnwrap(FinalScorePrediction.evaluate(scheme: decimal, finalComponentID: "final", targetPercent: 60).minimum), 51.4285714286, accuracy: 1e-8)
        var percent = scheme()
        percent.branches = [[GradeTerm(componentID: "work", weight: 30), GradeTerm(componentID: "final", weight: 70)]]
        XCTAssertEqual(FinalScorePrediction.evaluate(scheme: percent, finalComponentID: "final", targetPercent: 60).status, .invalidRule)
    }

    func testStructurallyInvalidRulesAreRejected() {
        var duplicate = scheme()
        duplicate.components.append(GradeComponent(id: "work", name: "平时二"))
        XCTAssertEqual(FinalScorePrediction.evaluate(scheme: duplicate, finalComponentID: "final", targetPercent: 60).status, .invalidRule)
        var rule = scheme()
        rule.branches = []
        XCTAssertEqual(FinalScorePrediction.evaluate(scheme: rule, finalComponentID: "final", targetPercent: 60).status, .invalidRule)
        rule.branches = [[]]
        XCTAssertEqual(FinalScorePrediction.evaluate(scheme: rule, finalComponentID: "final", targetPercent: 60).status, .invalidRule)
        rule.branches = [[GradeTerm(componentID: "unknown", weight: 1)]]
        XCTAssertEqual(FinalScorePrediction.evaluate(scheme: rule, finalComponentID: "final", targetPercent: 60).status, .invalidRule)
        var zero = scheme()
        zero.scale = 0
        XCTAssertEqual(FinalScorePrediction.evaluate(scheme: zero, finalComponentID: "final", targetPercent: 60).status, .invalidRule)
    }
}
