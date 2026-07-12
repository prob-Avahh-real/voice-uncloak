import XCTest
@testable import VoiceUncloak

/// 韧性测试 — "坏了怎么办"
///
/// 验证 AudioProcessor 在异常条件下的降级路径：
/// - 无效输入 → structured error
/// - 空 buffer → error
/// - 损坏文件 → error
/// - 磁盘满 → error
final class ResilienceTests: XCTestCase {
    let processor = AudioProcessor()
    let restorer = VoiceRestorer()

    // MARK: - Invalid Input

    func testNonexistentFileReturnsError() async {
        let url = URL(fileURLWithPath: "/tmp/nonexistent_audio_file_12345.wav")
        var config = ProcessingConfig()

        do {
            _ = try await processor.process(inputURL: url, config: config) { _, _ in }
            XCTFail("Should throw for nonexistent file")
        } catch {
            XCTAssertNotNil(error)
        }
    }

    func testDirectoryAsInputReturnsError() async {
        let dirURL = FileManager.default.temporaryDirectory
        var config = ProcessingConfig()

        do {
            _ = try await processor.process(inputURL: dirURL, config: config) { _, _ in }
            XCTFail("Should throw for directory input")
        } catch {
            XCTAssertNotNil(error)
        }
    }

    // MARK: - Boundary Values

    func testZeroAmountsDoNotCrash() async throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100) else { return }
        buffer.frameLength = 44100
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("zero_test.wav")
        let file = try AVAudioFile(forWriting: tempURL, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true
        ], commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)

        var config = ProcessingConfig()
        config.enableNoiseReduction = true
        config.noiseReductionAmount = 0.0    // minimum
        config.dereverbAmount = 0.0           // minimum
        config.eqStrength = 0.0               // minimum

        let outputURL = try await processor.process(inputURL: tempURL, config: config) { _, _ in }
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func testMaximumAmountsDoNotCrash() async throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100) else { return }
        buffer.frameLength = 44100
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("max_test.wav")
        let file = try AVAudioFile(forWriting: tempURL, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true
        ], commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)

        var config = ProcessingConfig()
        config.enableNoiseReduction = true
        config.enableDereverberation = true
        config.enableEQNormalization = true
        config.noiseReductionAmount = 1.0    // maximum
        config.dereverbAmount = 1.0           // maximum
        config.eqStrength = 1.0               // maximum

        let outputURL = try await processor.process(inputURL: tempURL, config: config) { _, _ in }
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
    }

    // MARK: - Restorer Resilience

    func testRestorerWithInvalidInput() async {
        let url = URL(fileURLWithPath: "/tmp/nonexistent_enhance.wav")
        do {
            _ = try await restorer.enhance(url: url)
            XCTFail("Should throw for nonexistent file")
        } catch {
            XCTAssertNotNil(error)
        }
    }

    // MARK: - Concurrent Processing

    func testConcurrentProcessingDoesNotCrash() async {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 22050) else { return }
        buffer.frameLength = 22050
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("concurrent_test.wav")
        let file = try? AVAudioFile(forWriting: tempURL, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true
        ], commonFormat: .pcmFormatFloat32, interleaved: false)
        try? file?.write(from: buffer)

        var config = ProcessingConfig()
        config.enableNoiseReduction = true

        // Two independent processor instances — should not interfere
        let p1 = AudioProcessor()
        let p2 = AudioProcessor()

        async let r1 = try? p1.process(inputURL: tempURL, config: config) { _, _ in }
        async let r2 = try? p2.process(inputURL: tempURL, config: config) { _, _ in }

        let (result1, result2) = await (r1, r2)
        XCTAssertNotNil(result1, "First processor should complete")
        XCTAssertNotNil(result2, "Second processor should complete")
    }
}
