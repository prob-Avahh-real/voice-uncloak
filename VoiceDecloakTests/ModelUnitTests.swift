import XCTest
@testable import VoiceUncloak

/// Model 层单元测试 — AudioFile, ProcessingConfig, 枚举
final class ModelUnitTests: XCTestCase {

    // MARK: - AudioFile

    func testAudioFileIdentity() {
        let url = URL(fileURLWithPath: "/test/audio.wav")
        let file1 = AudioFile(url: url, name: "test.wav", duration: 120.5, sampleRate: 44100, channelCount: 2)
        let file2 = AudioFile(url: url, name: "test.wav", duration: 120.5, sampleRate: 44100, channelCount: 2)

        // Different UUIDs → different identity
        XCTAssertNotEqual(file1.id, file2.id)
        XCTAssertNotEqual(file1, file2)
    }

    func testDisplayDurationFormatting() {
        let file = AudioFile(url: URL(fileURLWithPath: "/test.wav"), name: "test", duration: 185, sampleRate: 44100, channelCount: 1)
        XCTAssertEqual(file.displayDuration, "3:05")

        let short = AudioFile(url: URL(fileURLWithPath: "/s.wav"), name: "s", duration: 45, sampleRate: 44100, channelCount: 1)
        XCTAssertEqual(short.displayDuration, "0:45")

        let edge = AudioFile(url: URL(fileURLWithPath: "/e.wav"), name: "e", duration: 0, sampleRate: 44100, channelCount: 1)
        XCTAssertEqual(edge.displayDuration, "0:00")
    }

    // MARK: - ProcessingTechnique

    func testAllTechniquesHaveUniqueIDs() {
        let ids = ProcessingTechnique.allCases.map { $0.id }
        XCTAssertEqual(ids.count, Set(ids).count, "All technique IDs should be unique")
    }

    func testTechniqueDescriptionsAreNotEmpty() {
        for technique in ProcessingTechnique.allCases {
            XCTAssertFalse(technique.description.isEmpty, "\(technique.rawValue) should have description")
        }
    }

    func testTechniqueSymbolsAreValid() {
        for technique in ProcessingTechnique.allCases {
            XCTAssertFalse(technique.symbol.isEmpty, "\(technique.rawValue) should have SF Symbol")
        }
    }

    func testTechniqueCount() {
        XCTAssertEqual(ProcessingTechnique.allCases.count, 5, "5 processing techniques expected")
    }

    // MARK: - ProcessingConfig

    func testDefaultConfigDisablesAdvanced() {
        let config = ProcessingConfig()
        XCTAssertTrue(config.enableNoiseReduction, "Noise reduction on by default")
        XCTAssertTrue(config.enableDereverberation, "Dereverb on by default")
        XCTAssertTrue(config.enableEQNormalization, "EQ norm on by default")
        XCTAssertFalse(config.enablePitchCorrection, "Pitch correction off by default")
        XCTAssertFalse(config.enableSpeechEnhancement, "Speech enhancement off by default")
    }

    func testConfigValuesInRange() {
        let config = ProcessingConfig()
        XCTAssertTrue(config.noiseReductionAmount >= 0 && config.noiseReductionAmount <= 1.0)
        XCTAssertTrue(config.dereverbAmount >= 0 && config.dereverbAmount <= 1.0)
        XCTAssertTrue(config.eqStrength >= 0 && config.eqStrength <= 1.0)
        XCTAssertGreaterThan(config.pitchTolerance, 0)
    }

    // MARK: - ProcessingState

    func testIsProcessingOnlyTrueDuringProcessing() {
        XCTAssertFalse(ProcessingState.idle.isProcessing)
        XCTAssertFalse(ProcessingState.loading.isProcessing)
        XCTAssertTrue(ProcessingState.processing(progress: 0.5, currentStep: "test").isProcessing)
        XCTAssertFalse(ProcessingState.completed(outputURL: URL(fileURLWithPath: "/tmp")).isProcessing)
        XCTAssertFalse(ProcessingState.error(message: "err").isProcessing)
    }

    func testProcessingStateEquality() {
        let a = ProcessingState.processing(progress: 0.5, currentStep: "test")
        let b = ProcessingState.processing(progress: 0.5, currentStep: "test")
        XCTAssertEqual(a, b)

        let c = ProcessingState.processing(progress: 0.6, currentStep: "test")
        XCTAssertNotEqual(a, c)
    }

    // MARK: - AudioProcessorError

    func testErrorDescriptionsAreNotEmpty() {
        let errors: [AudioProcessorError] = [
            .invalidInput,
            .bufferAllocationFailed,
            .exportFailed("test")
        ]
        for error in errors {
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true, "Error should have description")
        }
    }

    func testExportFailedIncludesMessage() {
        let error = AudioProcessorError.exportFailed("磁盘已满")
        XCTAssertTrue(error.errorDescription?.contains("磁盘已满") ?? false)
    }
}
