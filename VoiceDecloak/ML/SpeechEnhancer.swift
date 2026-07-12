import Foundation
import AVFoundation
import Accelerate

// MARK: - Voice Restorer (ML-based)

/// ML-based speech enhancement layer.
/// Uses spectral envelope reconstruction to further reduce artifacts.
/// CoreML model can be plugged in when available.
final class VoiceRestorer: @unchecked Sendable {

    /// Enhance audio using spectral smoothing and harmonic reconstruction.
    /// Placeholder for CoreML model; currently uses heuristic enhancement.
    func enhance(url: URL) async throws -> URL {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw AudioProcessorError.bufferAllocationFailed
        }
        try file.read(into: buffer)
        guard let data = buffer.floatChannelData?[0] else {
            throw AudioProcessorError.invalidInput
        }

        let nFrames = Int(buffer.frameLength)

        // --- Spectral smoothing: reduce residual artifacts ---
        let fftSize = min(2048, 1 << Int(floor(log2(Float(nFrames)))))
        let hopSize = fftSize / 4
        let windowCount = max(1, (nFrames - fftSize) / hopSize + 1)

        guard let fftSetup = vDSP_create_fftsetup(vDSP_Length(log2(Float(fftSize))), FFTRadix(kFFTRadix2)) else {
            return url
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        let outputData = UnsafeMutablePointer<Float>.allocate(capacity: nFrames)
        outputData.initialize(repeating: 0, count: nFrames)
        defer { outputData.deallocate() }

        // Apply spectral smoothing: replace each magnitude bin with
        // weighted average of neighbors, reducing isolated artifacts
        let smoothingRadius = 3

        for w in 0..<windowCount {
            let start = w * hopSize
            var windowed = [Float](repeating: 0, count: fftSize)
            for i in 0..<min(fftSize, nFrames - start) {
                windowed[i] = data[start + i]
            }
            var hannWindow = [Float](repeating: 0, count: fftSize)
            vDSP_hann_window(&hannWindow, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
            vDSP_vmul(windowed, 1, hannWindow, 1, &windowed, 1, vDSP_Length(fftSize))

            var realPart = [Float](repeating: 0, count: fftSize / 2)
            var imagPart = [Float](repeating: 0, count: fftSize / 2)

            windowed.withUnsafeMutableBufferPointer { buf in
                var cplx = DSPSplitComplex(realp: buf.baseAddress!, imagp: [Float](repeating: 0, count: fftSize))
                buf.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) { ptr in
                    vDSP_ctoz(ptr, 2, &cplx, 1, vDSP_Length(fftSize / 2))
                }
                vDSP_fft_zrip(fftSetup, &cplx, 1, vDSP_Length(log2(Float(fftSize))), FFTDirection(kFFTDirection_Forward))
                for i in 0..<(fftSize / 2) {
                    realPart[i] = cplx.realp[i]
                    imagPart[i] = cplx.imagp[i]
                }
            }

            // Smooth magnitude spectrum
            var mag = [Float](repeating: 0, count: fftSize / 2)
            var splitComplex = DSPSplitComplex(realp: &realPart, imagp: &imagPart)
            vDSP_zvmags(&splitComplex, 1, &mag, 1, vDSP_Length(fftSize / 2))
            for i in 0..<(fftSize / 2) { mag[i] = sqrt(mag[i]) }

            var smoothedMag = mag
            for i in 0..<(fftSize / 2) {
                var sum: Float = 0
                var count: Int = 0
                for j in max(0, i - smoothingRadius)...min(fftSize / 2 - 1, i + smoothingRadius) {
                    sum += mag[j]
                    count += 1
                }
                smoothedMag[i] = sum / Float(count)
            }

            // Reconstruct: keep phase, apply smoothed magnitude
            for i in 0..<(fftSize / 2) {
                let gain = mag[i] > 1e-6 ? smoothedMag[i] / mag[i] : 1.0
                realPart[i] *= gain
                imagPart[i] *= gain
            }

            // Inverse FFT
            var outputFrame = [Float](repeating: 0, count: fftSize)
            outputFrame.withUnsafeMutableBufferPointer { buf in
                var cplx = DSPSplitComplex(realp: buf.baseAddress!, imagp: [Float](repeating: 0, count: fftSize))
                var src = DSPSplitComplex(realp: &realPart, imagp: &imagPart)
                buf.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) { ptr in
                    vDSP_ztoc(&src, 1, ptr, 2, vDSP_Length(fftSize / 2))
                }
                vDSP_fft_zrip(fftSetup, &cplx, 1, vDSP_Length(log2(Float(fftSize))), FFTDirection(kFFTDirection_Inverse))
            }
            var scale: Float = 1.0 / Float(fftSize)
            vDSP_vsmul(outputFrame, 1, &scale, &outputFrame, 1, vDSP_Length(fftSize))

            for i in 0..<min(fftSize, nFrames - start) {
                outputData[start + i] += outputFrame[i]
            }
        }

        // Normalize
        var maxVal: Float = 0
        vDSP_maxmgv(outputData, 1, &maxVal, vDSP_Length(nFrames))
        if maxVal > 1.0 {
            var scale = 1.0 / maxVal
            vDSP_vsmul(outputData, 1, &scale, outputData, 1, vDSP_Length(nFrames))
        }

        // Export enhanced audio
        let tempDir = FileManager.default.temporaryDirectory
        let outputURL = tempDir.appendingPathComponent("enhanced_\(UUID().uuidString.prefix(8)).wav")

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false
        ]

        guard let outputFile = try? AVAudioFile(
            forWriting: outputURL,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        ) else {
            throw AudioProcessorError.exportFailed("无法创建增强输出文件")
        }

        guard let outBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFile.processingFormat,
            frameCapacity: AVAudioFrameCount(nFrames)
        ) else {
            throw AudioProcessorError.bufferAllocationFailed
        }
        outBuffer.frameLength = AVAudioFrameCount(nFrames)
        if let dst = outBuffer.floatChannelData?[0] {
            dst.update(from: outputData, count: nFrames)
        }
        try outputFile.write(from: outBuffer)

        return outputURL
    }
}
