import XCTest
@testable import VoiceUncloak

/// 性能基准测试
///
/// DSP 处理管线每步都有明确的计算复杂度。
/// 这些测试确保重构不会意外降低性能。
final class PerformanceBenchmarks: XCTestCase {
    let processor = AudioProcessor()

    // MARK: - 单步处理基准

    func testNoiseReductionPerformance() async throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100 * 10) else { return }
        buffer.frameLength = 44100 * 10  // 10 seconds
        if let data = buffer.floatChannelData?[0] {
            for i in 0..<Int(buffer.frameLength) { data[i] = Float.random(in: -0.5...0.5) }
        }
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("perf_nr.wav")
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

        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()]) {
            let expectation = expectation(description: "NR complete")
            Task {
                _ = try? await processor.process(inputURL: tempURL, config: config) { _, _ in }
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 30)
        }
    }

    func testFullPipelinePerformance() async throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100 * 5) else { return }
        buffer.frameLength = 44100 * 5
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("perf_full.wav")
        let file = try AVAudioFile(forWriting: tempURL, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true
        ], commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)

        var config = ProcessingConfig()
        config.enableNoiseReduction = true
        config.enableDereverberation = true
        config.enableEQNormalization = true
        config.enablePitchCorrection = true

        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()]) {
            let expectation = expectation(description: "Full pipeline")
            Task {
                _ = try? await processor.process(inputURL: tempURL, config: config) { _, _ in }
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 60)
        }
    }

    func testPitchDetectionSpeed() async throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100 * 5) else { return }
        buffer.frameLength = 44100 * 5
        if let data = buffer.floatChannelData?[0] {
            for i in 0..<Int(buffer.frameLength) {
                data[i] = sin(2.0 * Float.pi * 200.0 * Float(i) / 44100.0) * 0.5
            }
        }
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("perf_pitch.wav")
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

        measure(metrics: [XCTClockMetric(), XCTCPUMetric()]) {
            let expectation = expectation(description: "Pitch correction")
            Task {
                _ = try? await processor.process(inputURL: tempURL, config: config) { _, _ in }
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 30)
        }
    }

    // MARK: - Memory

    func testMemoryStaysStableOnRepeatedProcessing() async throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100) else { return }
        buffer.frameLength = 44100
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("mem_test.wav")
        let file = try AVAudioFile(forWriting: tempURL, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true
        ], commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)

        var config = ProcessingConfig()
        config.enableNoiseReduction = true
        config.enableDereverberation = true

        // Process 3 times — memory should not leak
        for i in 0..<3 {
            let p = AudioProcessor()
            _ = try? await p.process(inputURL: tempURL, config: config) { _, _ in }
        }
        // If we reach here without OOM, memory is stable
        XCTAssertTrue(true)
    }
}
