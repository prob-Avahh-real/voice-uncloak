import XCTest
@testable import VoiceUncloak

/// VoiceRestorer (ML-based speech enhancement) 单元测试
final class VoiceRestorerUnitTests: XCTestCase {
    let restorer = VoiceRestorer()

    func testEnhanceCompletesWithoutCrash() async throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100) else { return }
        buffer.frameLength = 44100
        if let data = buffer.floatChannelData?[0] {
            for i in 0..<44100 { data[i] = sin(2.0 * Float.pi * 440 * Float(i) / 44100) * 0.3 }
        }
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("restore_input.wav")
        let file = try AVAudioFile(forWriting: tempURL, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true
        ], commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)

        let outputURL = try await restorer.enhance(url: tempURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func testEnhanceWithVeryShortAudio() async throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 100) else { return }
        buffer.frameLength = 100
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("short_enhance.wav")
        let file = try AVAudioFile(forWriting: tempURL, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true
        ], commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)

        let outputURL = try await restorer.enhance(url: tempURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func testEnhancePreservesFileFormat() async throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48000) else { return }
        buffer.frameLength = 48000
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("48k_test.wav")
        let file = try AVAudioFile(forWriting: tempURL, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true
        ], commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)

        let outputURL = try await restorer.enhance(url: tempURL)

        // Verify output file sample rate preserved
        let outputFile = try AVAudioFile(forReading: outputURL)
        XCTAssertEqual(outputFile.processingFormat.sampleRate, 48000, accuracy: 1.0)
    }
}
