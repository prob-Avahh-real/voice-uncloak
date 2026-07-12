import XCTest
@testable import VoiceUncloak

/// AudioProcessor 单元测试 — 5步DSP管线 + 错误路径
final class AudioProcessorUnitTests: XCTestCase {

    let processor = AudioProcessor()

    // MARK: - Pipeline Contract

    func testProcessPipelineCompletesWithoutCrash() async throws {
        // Given: 单声道 1kHz 正弦波 1秒 PCM buffer
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let frameCount = AVAudioFrameCount(44100)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            XCTFail("Buffer allocation failed")
            return
        }
        buffer.frameLength = frameCount
        if let data = buffer.floatChannelData?[0] {
            for i in 0..<Int(frameCount) {
                data[i] = sin(2.0 * Float.pi * 1000.0 * Float(i) / 44100.0) * 0.5
            }
        }

        // Write to temp file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_input.wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true
        ]
        guard let outputFile = try? AVAudioFile(forWriting: tempURL, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false) else {
            XCTFail("Cannot create test file"); return
        }
        try outputFile.write(from: buffer)

        // When: 全管线处理
        var config = ProcessingConfig()
        config.enableNoiseReduction = true
        config.enableDereverberation = true
        config.enableEQNormalization = true
        config.enablePitchCorrection = false
        config.noiseReductionAmount = 0.5
        config.dereverbAmount = 0.4
        config.eqStrength = 0.6

        // Then: 完成且不抛异常
        let outputURL = try await processor.process(inputURL: tempURL, config: config) { progress, step in
            XCTAssertTrue(progress >= 0 && progress <= 1.0, "Progress out of range: \(progress)")
            XCTAssertFalse(step.isEmpty, "Step description should not be empty")
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
    }

    // MARK: - Error Paths

    func testInvalidInputReturnsError() async {
        let invalidURL = URL(fileURLWithPath: "/nonexistent/audio.wav")
        var config = ProcessingConfig()
        do {
            _ = try await processor.process(inputURL: invalidURL, config: config) { _, _ in }
            XCTFail("Expected error for invalid input")
        } catch {
            XCTAssertNotNil(error)
        }
    }

    // MARK: - Progress Reporting

    func testProgressCallbacksAreInvoked() async throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let frameCount = AVAudioFrameCount(44100)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("progress_test.wav")
        let file = try AVAudioFile(forWriting: tempURL, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true
        ], commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)

        var progressValues: [Double] = []
        var stepNames: [String] = []

        var config = ProcessingConfig()
        config.enableNoiseReduction = true
        config.enableDereverberation = true
        config.enableEQNormalization = true

        _ = try await processor.process(inputURL: tempURL, config: config) { progress, step in
            progressValues.append(progress)
            stepNames.append(step)
        }

        XCTAssertFalse(progressValues.isEmpty, "Progress should have been reported")
        XCTAssertTrue(progressValues.last ?? 0 >= 0.9, "Final progress should be near 1.0")
        XCTAssertTrue(stepNames.contains { $0.contains("完成") }, "应该包含完成步骤")
    }

    // MARK: - Step Isolation

    func testNoiseReductionOnly() async throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100) else { return }
        buffer.frameLength = 44100
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("nr_test.wav")
        let file = try AVAudioFile(forWriting: tempURL, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true
        ], commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)

        var config = ProcessingConfig()
        config.enableNoiseReduction = true
        config.enableDereverberation = false
        config.enableEQNormalization = false
        config.enablePitchCorrection = false

        let outputURL = try await processor.process(inputURL: tempURL, config: config) { _, _ in }
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func testPitchCorrectionOnly() async throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100) else { return }
        buffer.frameLength = 44100
        if let data = buffer.floatChannelData?[0] {
            for i in 0..<44100 { data[i] = sin(2.0 * Float.pi * 200.0 * Float(i) / 44100.0) * 0.5 }
        }
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("pc_test.wav")
        let file = try AVAudioFile(forWriting: tempURL, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true
        ], commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)

        var config = ProcessingConfig()
        config.enableNoiseReduction = false
        config.enableDereverberation = false
        config.enableEQNormalization = false
        config.enablePitchCorrection = true
        config.pitchTolerance = 200

        let outputURL = try await processor.process(inputURL: tempURL, config: config) { _, _ in }
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
    }

    // MARK: - Edge Cases

    func testEmptyConfigAllDisabled() async throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1000) else { return }
        buffer.frameLength = 1000
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("empty_test.wav")
        let file = try AVAudioFile(forWriting: tempURL, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true
        ], commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)

        var config = ProcessingConfig()
        config.enableNoiseReduction = false
        config.enableDereverberation = false
        config.enableEQNormalization = false
        config.enablePitchCorrection = false

        // Should still export without error — all steps skipped
        let outputURL = try await processor.process(inputURL: tempURL, config: config) { _, _ in }
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func testVeryShortAudio() async throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 100) else { return }
        buffer.frameLength = 100
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("short_test.wav")
        let file = try AVAudioFile(forWriting: tempURL, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true
        ], commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)

        var config = ProcessingConfig()
        config.enableNoiseReduction = true

        let outputURL = try await processor.process(inputURL: tempURL, config: config) { _, _ in }
        // Very short audio should still produce output (not crash)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
    }
}
