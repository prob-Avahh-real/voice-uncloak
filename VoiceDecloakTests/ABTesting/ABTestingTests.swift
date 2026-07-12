import XCTest
@testable import VoiceUncloak

/// A/B 测试框架单元测试
final class ABTestingTests: XCTestCase {

    override func setUp() {
        ABTest.activeExperiments.removeAll()
    }

    func testVariantAssignmentIsDeterministic() {
        ABTest.register(key: "test_exp", variants: ["a", "b"], trafficSplit: [0.5, 0.5])

        let v1 = ABTest.variant(for: "test_exp", userId: "user-001")
        let v2 = ABTest.variant(for: "test_exp", userId: "user-001")

        XCTAssertEqual(v1, v2, "Same user should always get same variant")
    }

    func testTrafficSplitAccuracy() {
        ABTest.register(key: "split_test", variants: ["a", "b"], trafficSplit: [0.5, 0.5])

        var aCount = 0
        var bCount = 0
        let sampleSize = 1000

        for i in 0..<sampleSize {
            let v = ABTest.variant(for: "split_test", userId: "user-\(i)")
            if v == "a" { aCount += 1 }
            if v == "b" { bCount += 1 }
        }

        let aRatio = Double(aCount) / Double(sampleSize)
        let bRatio = Double(bCount) / Double(sampleSize)

        // Allow ±10% tolerance for random sampling
        XCTAssertTrue(aRatio > 0.4 && aRatio < 0.6, "A ratio \(aRatio) out of tolerance")
        XCTAssertTrue(bRatio > 0.4 && bRatio < 0.6, "B ratio \(bRatio) out of tolerance")
    }

    func testTripleVariantSplit() {
        ABTest.register(key: "triple", variants: ["a", "b", "c"], trafficSplit: [0.33, 0.33, 0.34])

        var counts = ["a": 0, "b": 0, "c": 0]
        for i in 0..<1000 {
            let v = ABTest.variant(for: "triple", userId: "u-\(i)")
            counts[v, default: 0] += 1
        }

        // Each variant should have ~333 users (±100)
        for (variant, count) in counts {
            XCTAssertTrue(count > 230 && count < 430, "\(variant) has \(count), expected ~333")
        }
    }

    func testUnregisteredExperimentReturnsControl() {
        let v = ABTest.variant(for: "nonexistent")
        XCTAssertEqual(v, "control")
    }

    func testMismatchedSplitsReturnControl() {
        ABTest.register(key: "bad", variants: ["a", "b"], trafficSplit: [0.5]) // missing one split
        let v = ABTest.variant(for: "bad")
        XCTAssertEqual(v, "control")
    }

    func testAllExperimentsInitialize() {
        ABTest.initializeExperiments()

        for experiment in ABTest.Experiment.allCases {
            XCTAssertNotNil(ABTest.activeExperiments[experiment.rawValue],
                           "\(experiment.rawValue) should be registered")
        }
    }

    // MARK: - Metrics

    func testCompletionRate() {
        var metrics = ABTestMetrics()
        metrics.exposures = ["a": 100, "b": 100]
        metrics.completions = ["a": 80, "b": 50]

        XCTAssertEqual(metrics.completionRate(for: "a"), 0.8, accuracy: 0.01)
        XCTAssertEqual(metrics.completionRate(for: "b"), 0.5, accuracy: 0.01)
    }

    func testErrorRate() {
        var metrics = ABTestMetrics()
        metrics.exposures = ["a": 100, "b": 100]
        metrics.errors = ["a": 5, "b": 20]

        XCTAssertEqual(metrics.errorRate(for: "a"), 0.05, accuracy: 0.01)
        XCTAssertEqual(metrics.errorRate(for: "b"), 0.20, accuracy: 0.01)
    }

    func testZeroDivisionProtected() {
        let metrics = ABTestMetrics()
        XCTAssertEqual(metrics.completionRate(for: "nonexistent"), 0.0)
        XCTAssertEqual(metrics.errorRate(for: "nonexistent"), 0.0)
    }
}
