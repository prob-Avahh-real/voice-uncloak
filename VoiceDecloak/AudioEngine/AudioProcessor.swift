import Foundation
import AVFoundation
import Accelerate

// MARK: - Processing Error

enum AudioProcessorError: LocalizedError {
    case invalidInput
    case bufferAllocationFailed
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidInput:          return "无效的输入文件"
        case .bufferAllocationFailed: return "音频缓冲区分配失败"
        case .exportFailed(let msg):  return "导出失败: \(msg)"
        }
    }
}

// MARK: - Audio Processor

final class AudioProcessor: @unchecked Sendable {

    func process(
        inputURL: URL,
        config: ProcessingConfig,
        progressHandler: @escaping @Sendable (Double, String) -> Void
    ) async throws -> URL {
        // Read input file into PCM buffer(s)
        let (buffers, format) = try await readPCMBuffers(from: inputURL)
        guard !buffers.isEmpty else { throw AudioProcessorError.invalidInput }

        var workingBuffers = buffers
        let totalSteps = [
            config.enableNoiseReduction,
            config.enableDereverberation,
            config.enableEQNormalization,
            config.enablePitchCorrection
        ].filter { $0 }.count
        var step = 0

        // --- 1. Noise Reduction (Spectral Subtraction) ---
        if config.enableNoiseReduction {
            step += 1
            progressHandler(Double(step) / Double(totalSteps + 1), "降噪处理...")
            workingBuffers = workingBuffers.map {
                applySpectralSubtraction(buffer: $0, format: format, amount: config.noiseReductionAmount)
            }
        }

        // --- 2. Dereverberation ---
        if config.enableDereverberation {
            step += 1
            progressHandler(Double(step) / Double(totalSteps + 1), "去混响...")
            workingBuffers = workingBuffers.map {
                applyDereverberation(buffer: $0, format: format, amount: config.dereverbAmount)
            }
        }

        // --- 3. EQ Normalization (spectral envelope flattening) ---
        if config.enableEQNormalization {
            step += 1
            progressHandler(Double(step) / Double(totalSteps + 1), "EQ 展平...")
            workingBuffers = workingBuffers.map {
                applyEQNormalization(buffer: $0, format: format, strength: config.eqStrength)
            }
        }

        // --- 4. Pitch Correction (auto-detect and reverse pitch shift) ---
        if config.enablePitchCorrection {
            step += 1
            progressHandler(Double(step) / Double(totalSteps + 1), "基频检测与还原...")
            workingBuffers = workingBuffers.map {
                applyPitchCorrection(buffer: $0, format: format, tolerance: config.pitchTolerance)
            }
        }

        // Export to temporary file
        progressHandler(0.95, "导出音频...")
        let outputURL = try await exportBuffers(workingBuffers, format: format)

        progressHandler(1.0, "完成")
        return outputURL
    }

    // MARK: - PCM Reader

    private func readPCMBuffers(from url: URL) async throws -> ([AVAudioPCMBuffer], AVAudioFormat) {
        let file = try AVAudioFile(forReading: url)
        guard let format = file.processingFormat.settings[AVSampleRateKey] as? Double,
              format > 0 else {
            throw AudioProcessorError.invalidInput
        }

        let pcmFormat = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: frameCount) else {
            throw AudioProcessorError.bufferAllocationFailed
        }
        try file.read(into: buffer)

        // Split into channel buffers for per-channel processing
        var channelBuffers: [AVAudioPCMBuffer] = []
        let channelCount = Int(pcmFormat.channelCount)

        for ch in 0..<channelCount {
            guard let chBuffer = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: frameCount) else {
                throw AudioProcessorError.bufferAllocationFailed
            }
            chBuffer.frameLength = frameCount
            if let src = buffer.floatChannelData?[ch],
               let dst = chBuffer.floatChannelData?[0] {
                dst.update(from: src, count: Int(frameCount))
            }
            channelBuffers.append(chBuffer)
        }

        return (channelBuffers, pcmFormat)
    }

    // MARK: - Spectral Subtraction (Noise Reduction)

    /// Classic spectral subtraction: estimate noise floor from quietest frames
    /// and subtract it from the magnitude spectrum.
    private func applySpectralSubtraction(
        buffer: AVAudioPCMBuffer,
        format: AVAudioFormat,
        amount: Float
    ) -> AVAudioPCMBuffer {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0, let data = buffer.floatChannelData?[0] else { return buffer }

        // FFT size: next power of two, max 4096
        let fftSize = min(4096, 1 << Int(floor(log2(Float(frameCount)))))
        let hopSize = fftSize / 4
        let windowCount = max(1, (frameCount - fftSize) / hopSize + 1)

        guard let fftSetup = vDSP_create_fftsetup(vDSP_Length(log2(Float(fftSize))), FFTRadix(kFFTRadix2)) else {
            return buffer
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        // Noise profile estimation: take the 5 quietest frames
        var frameEnergies: [(index: Int, energy: Float)] = []
        for w in 0..<windowCount {
            let start = w * hopSize
            var windowed = [Float](repeating: 0, count: fftSize)
            for i in 0..<min(fftSize, frameCount - start) {
                windowed[i] = data[start + i]
            }
            var energy: Float = 0
            vDSP_svesq(windowed, 1, &energy, vDSP_Length(windowed.count))
            frameEnergies.append((w, energy))
        }
        frameEnergies.sort { $0.energy < $1.energy }
        let noiseFrameCount = min(5, frameEnergies.count)
        let noiseIndices = Set(frameEnergies.prefix(noiseFrameCount).map { $0.index })

        // Compute noise magnitude average
        var noiseMagnitudes = [Float](repeating: 0, count: fftSize / 2)
        var noiseFrameContrib: Float = 0
        for w in 0..<windowCount {
            guard noiseIndices.contains(w) else { continue }
            noiseFrameContrib += 1
            let start = w * hopSize
            var realPart = [Float](repeating: 0, count: fftSize / 2)
            var imagPart = [Float](repeating: 0, count: fftSize / 2)
            var splitComplex = DSPSplitComplex(realp: &realPart, imagp: &imagPart)

            var windowed = [Float](repeating: 0, count: fftSize)
            for i in 0..<min(fftSize, frameCount - start) {
                windowed[i] = data[start + i]
            }

            windowed.withUnsafeMutableBufferPointer { buf in
                var cplx = DSPSplitComplex(realp: buf.baseAddress!, imagp: [Float](repeating: 0, count: fftSize))
                buf.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) { ptr in
                    vDSP_ctoz(ptr, 2, &cplx, 1, vDSP_Length(fftSize / 2))
                }
                vDSP_fft_zrip(fftSetup, &cplx, 1, vDSP_Length(log2(Float(fftSize))), FFTDirection(kFFTDirection_Forward))
                // Now split into real/imag
                for i in 0..<(fftSize / 2) {
                    splitComplex.realp[i] = cplx.realp[i]
                    splitComplex.imagp[i] = cplx.imagp[i]
                }
            }

            var mag = [Float](repeating: 0, count: fftSize / 2)
            vDSP_zvmags(&splitComplex, 1, &mag, 1, vDSP_Length(fftSize / 2))
            for i in 0..<(fftSize / 2) {
                mag[i] = sqrt(mag[i])
            }
            vDSP_vadd(mag, 1, noiseMagnitudes, 1, &noiseMagnitudes, 1, vDSP_Length(fftSize / 2))
        }
        if noiseFrameContrib > 0 {
            var scale = 1.0 / noiseFrameContrib
            vDSP_vsmul(noiseMagnitudes, 1, &scale, &noiseMagnitudes, 1, vDSP_Length(fftSize / 2))
        }

        // Process each frame with spectral subtraction + overlap-add
        let outputData = UnsafeMutablePointer<Float>.allocate(capacity: frameCount)
        outputData.initialize(repeating: 0, count: frameCount)
        defer { outputData.deallocate() }

        let clampedAmount = min(1.0, max(0.1, amount))
        let oversubtraction: Float = 1.0 + clampedAmount * 3.0  // 1x-4x oversubtraction

        for w in 0..<windowCount {
            let start = w * hopSize
            var realPart = [Float](repeating: 0, count: fftSize / 2)
            var imagPart = [Float](repeating: 0, count: fftSize / 2)
            var splitComplex = DSPSplitComplex(realp: &realPart, imagp: &imagPart)

            var windowed = [Float](repeating: 0, count: fftSize)
            for i in 0..<min(fftSize, frameCount - start) {
                windowed[i] = data[start + i]
            }
            // Apply Hann window
            var hannWindow = [Float](repeating: 0, count: fftSize)
            vDSP_hann_window(&hannWindow, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
            vDSP_vmul(windowed, 1, hannWindow, 1, &windowed, 1, vDSP_Length(fftSize))

            // FFT
            windowed.withUnsafeMutableBufferPointer { buf in
                var cplx = DSPSplitComplex(realp: buf.baseAddress!, imagp: [Float](repeating: 0, count: fftSize))
                buf.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) { ptr in
                    vDSP_ctoz(ptr, 2, &cplx, 1, vDSP_Length(fftSize / 2))
                }
                vDSP_fft_zrip(fftSetup, &cplx, 1, vDSP_Length(log2(Float(fftSize))), FFTDirection(kFFTDirection_Forward))
                for i in 0..<(fftSize / 2) {
                    splitComplex.realp[i] = cplx.realp[i]
                    splitComplex.imagp[i] = cplx.imagp[i]
                }
            }

            // Spectral subtraction on magnitude
            var mag = [Float](repeating: 0, count: fftSize / 2)
            vDSP_zvmags(&splitComplex, 1, &mag, 1, vDSP_Length(fftSize / 2))
            for i in 0..<(fftSize / 2) {
                mag[i] = sqrt(mag[i])
            }

            for i in 0..<(fftSize / 2) {
                let noiseFloor = noiseMagnitudes[i] * oversubtraction
                var gain: Float = 1.0
                if mag[i] > noiseFloor {
                    gain = (mag[i] - noiseFloor) / mag[i]
                } else {
                    gain = 0.001  // -60 dB floor
                }
                // Smooth gain to avoid musical noise
                gain = min(gain, 1.0)
                gain = max(gain, 0.001)
                splitComplex.realp[i] *= gain
                splitComplex.imagp[i] *= gain
            }

            // Inverse FFT
            var outputFrame = [Float](repeating: 0, count: fftSize)
            outputFrame.withUnsafeMutableBufferPointer { buf in
                var cplx = DSPSplitComplex(realp: buf.baseAddress!, imagp: [Float](repeating: 0, count: fftSize))
                // Pack split complex
                buf.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) { ptr in
                    var src = splitComplex
                    vDSP_ztoc(&src, 1, ptr, 2, vDSP_Length(fftSize / 2))
                }
                vDSP_fft_zrip(fftSetup, &cplx, 1, vDSP_Length(log2(Float(fftSize))), FFTDirection(kFFTDirection_Inverse))
            }
            // Scale by 1/fftSize
            var scale: Float = 1.0 / Float(fftSize)
            vDSP_vsmul(outputFrame, 1, &scale, &outputFrame, 1, vDSP_Length(fftSize))

            // Overlap-add
            for i in 0..<min(fftSize, frameCount - start) {
                outputData[start + i] += outputFrame[i]
            }
        }

        // Normalize
        var maxVal: Float = 0
        vDSP_maxmgv(outputData, 1, &maxVal, vDSP_Length(frameCount))
        if maxVal > 1.0 {
            var scale = 1.0 / maxVal
            vDSP_vsmul(outputData, 1, &scale, outputData, 1, vDSP_Length(frameCount))
        }

        let outBuffer = cloneBuffer(buffer, with: outputData, frameCount: frameCount)
        return outBuffer
    }

    // MARK: - Dereverberation

    /// Reduces reverberation by applying spectral smoothing and
    /// attenuating the late-field (decaying tail) of the signal.
    private func applyDereverberation(
        buffer: AVAudioPCMBuffer,
        format: AVAudioFormat,
        amount: Float
    ) -> AVAudioPCMBuffer {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0, let data = buffer.floatChannelData?[0] else { return buffer }

        // Simple approach: spectral subtraction in the log-magnitude domain
        // to remove the smoothed (reverb) component
        let fftSize = min(2048, 1 << Int(floor(log2(Float(frameCount)))))
        let hopSize = fftSize / 4
        let windowCount = max(1, (frameCount - fftSize) / hopSize + 1)

        guard let fftSetup = vDSP_create_fftsetup(vDSP_Length(log2(Float(fftSize))), FFTRadix(kFFTRadix2)) else {
            return buffer
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        let outputData = UnsafeMutablePointer<Float>.allocate(capacity: frameCount)
        outputData.initialize(repeating: 0, count: frameCount)
        defer { outputData.deallocate() }

        let historyCount = 3 // number of past frames to average for reverb estimate
        var magHistory: [[Float]] = []

        let clampedAmount = min(1.0, max(0.0, amount))
        let suppression: Float = 0.1 + clampedAmount * 0.8  // 0.1x - 0.9x

        for w in 0..<windowCount {
            let start = w * hopSize
            var realPart = [Float](repeating: 0, count: fftSize / 2)
            var imagPart = [Float](repeating: 0, count: fftSize / 2)
            var splitComplex = DSPSplitComplex(realp: &realPart, imagp: &imagPart)

            var windowed = [Float](repeating: 0, count: fftSize)
            for i in 0..<min(fftSize, frameCount - start) {
                windowed[i] = data[start + i]
            }
            var hannWindow = [Float](repeating: 0, count: fftSize)
            vDSP_hann_window(&hannWindow, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
            vDSP_vmul(windowed, 1, hannWindow, 1, &windowed, 1, vDSP_Length(fftSize))

            windowed.withUnsafeMutableBufferPointer { buf in
                var cplx = DSPSplitComplex(realp: buf.baseAddress!, imagp: [Float](repeating: 0, count: fftSize))
                buf.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) { ptr in
                    vDSP_ctoz(ptr, 2, &cplx, 1, vDSP_Length(fftSize / 2))
                }
                vDSP_fft_zrip(fftSetup, &cplx, 1, vDSP_Length(log2(Float(fftSize))), FFTDirection(kFFTDirection_Forward))
                for i in 0..<(fftSize / 2) {
                    splitComplex.realp[i] = cplx.realp[i]
                    splitComplex.imagp[i] = cplx.imagp[i]
                }
            }

            var mag = [Float](repeating: 0, count: fftSize / 2)
            vDSP_zvmags(&splitComplex, 1, &mag, 1, vDSP_Length(fftSize / 2))
            for i in 0..<(fftSize / 2) {
                mag[i] = sqrt(mag[i])
            }

            // Estimate reverb as average of past magnitude spectra
            if !magHistory.isEmpty {
                var reverbEstimate = [Float](repeating: 0, count: fftSize / 2)
                for h in magHistory {
                    vDSP_vadd(h, 1, reverbEstimate, 1, &reverbEstimate, 1, vDSP_Length(fftSize / 2))
                }
                var scale = 1.0 / Float(magHistory.count)
                vDSP_vsmul(reverbEstimate, 1, &scale, &reverbEstimate, 1, vDSP_Length(fftSize / 2))

                // Subtract smoothed (reverb) from current and keep the transient (direct sound + early reflections)
                for i in 0..<(fftSize / 2) {
                    let direct = max(0, mag[i] - reverbEstimate[i] * suppression)
                    let gain = mag[i] > 0.0001 ? min(1.0, direct / mag[i]) : 1.0
                    splitComplex.realp[i] *= gain
                    splitComplex.imagp[i] *= gain
                }
            }

            magHistory.append(mag)
            if magHistory.count > historyCount {
                magHistory.removeFirst()
            }

            // Inverse FFT
            var outputFrame = [Float](repeating: 0, count: fftSize)
            outputFrame.withUnsafeMutableBufferPointer { buf in
                var cplx = DSPSplitComplex(realp: buf.baseAddress!, imagp: [Float](repeating: 0, count: fftSize))
                buf.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) { ptr in
                    var src = splitComplex
                    vDSP_ztoc(&src, 1, ptr, 2, vDSP_Length(fftSize / 2))
                }
                vDSP_fft_zrip(fftSetup, &cplx, 1, vDSP_Length(log2(Float(fftSize))), FFTDirection(kFFTDirection_Inverse))
            }
            var scale: Float = 1.0 / Float(fftSize)
            vDSP_vsmul(outputFrame, 1, &scale, &outputFrame, 1, vDSP_Length(fftSize))

            for i in 0..<min(fftSize, frameCount - start) {
                outputData[start + i] += outputFrame[i]
            }
        }

        var maxVal: Float = 0
        vDSP_maxmgv(outputData, 1, &maxVal, vDSP_Length(frameCount))
        if maxVal > 1.0 {
            var scale = 1.0 / maxVal
            vDSP_vsmul(outputData, 1, &scale, outputData, 1, vDSP_Length(frameCount))
        }

        return cloneBuffer(buffer, with: outputData, frameCount: frameCount)
    }

    // MARK: - EQ Normalization

    /// Flattens the long-term magnitude spectrum so that artificial
    /// EQ curves (telephone bandpass, bass boost, etc.) are undone.
    private func applyEQNormalization(
        buffer: AVAudioPCMBuffer,
        format: AVAudioFormat,
        strength: Float
    ) -> AVAudioPCMBuffer {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0, let data = buffer.floatChannelData?[0] else { return buffer }

        let fftSize = min(4096, 1 << Int(floor(log2(Float(frameCount)))))
        let hopSize = fftSize / 2
        let windowCount = max(1, (frameCount - fftSize) / hopSize + 1)

        guard let fftSetup = vDSP_create_fftsetup(vDSP_Length(log2(Float(fftSize))), FFTRadix(kFFTRadix2)) else {
            return buffer
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        // Compute long-term average magnitude spectrum
        var avgMag = [Float](repeating: 0, count: fftSize / 2)
        var frameCountFloat: Float = 0

        for w in 0..<windowCount {
            let start = w * hopSize
            var windowed = [Float](repeating: 0, count: fftSize)
            for i in 0..<min(fftSize, frameCount - start) {
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

            var mag = [Float](repeating: 0, count: fftSize / 2)
            var splitComplex = DSPSplitComplex(realp: &realPart, imagp: &imagPart)
            vDSP_zvmags(&splitComplex, 1, &mag, 1, vDSP_Length(fftSize / 2))
            for i in 0..<(fftSize / 2) { mag[i] = sqrt(mag[i]) }
            vDSP_vadd(mag, 1, avgMag, 1, &avgMag, 1, vDSP_Length(fftSize / 2))
            frameCountFloat += 1
        }

        if frameCountFloat > 0 {
            var scale = 1.0 / frameCountFloat
            vDSP_vsmul(avgMag, 1, &scale, &avgMag, 1, vDSP_Length(fftSize / 2))
        }

        // Compute inverse EQ: boost frequency bins that are weak, cut those that are strong
        var eqGain = [Float](repeating: 1.0, count: fftSize / 2)
        let clampStrength = min(1.0, max(0.0, strength))

        for i in 0..<(fftSize / 2) {
            if avgMag[i] > 1e-6 {
                // Desired: flat spectrum → gain = target_flat / current
                // target_flat = geometric mean of non-zero bins
                let target: Float = 0.1 // conservative target
                let rawGain = target / avgMag[i]
                // Clamp to reasonable range and blend with original
                let clampedGain = min(10.0, max(0.1, rawGain))
                eqGain[i] = 1.0 + (clampedGain - 1.0) * clampStrength
            }
        }

        // Apply EQ in frequency domain
        let outputData = UnsafeMutablePointer<Float>.allocate(capacity: frameCount)
        outputData.initialize(repeating: 0, count: frameCount)
        defer { outputData.deallocate() }

        for w in 0..<windowCount {
            let start = w * hopSize
            var windowed = [Float](repeating: 0, count: fftSize)
            for i in 0..<min(fftSize, frameCount - start) {
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

            // Apply EQ gains
            for i in 0..<(fftSize / 2) {
                realPart[i] *= eqGain[i]
                imagPart[i] *= eqGain[i]
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

            for i in 0..<min(fftSize, frameCount - start) {
                outputData[start + i] += outputFrame[i]
            }
        }

        var maxVal: Float = 0
        vDSP_maxmgv(outputData, 1, &maxVal, vDSP_Length(frameCount))
        if maxVal > 1.0 {
            var scale = 1.0 / maxVal
            vDSP_vsmul(outputData, 1, &scale, outputData, 1, vDSP_Length(frameCount))
        }

        return cloneBuffer(buffer, with: outputData, frameCount: frameCount)
    }

    // MARK: - Pitch Correction

    /// Detects the dominant pitch using autocorrelation and
    /// compares against expected human voice range to estimate
    /// and reverse a pitch shift.
    private func applyPitchCorrection(
        buffer: AVAudioPCMBuffer,
        format: AVAudioFormat,
        tolerance: Float
    ) -> AVAudioPCMBuffer {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0, let data = buffer.floatChannelData?[0] else { return buffer }

        // Detect dominant pitch via autocorrelation
        let sampleRate = Float(format.sampleRate)
        let minPeriod = Int(sampleRate / 400)   // ~400 Hz max
        let maxPeriod = Int(sampleRate / 50)    // ~50 Hz min

        // Only analyze middle portion (avoid silence at start/end)
        let analyzeStart = frameCount / 4
        let analyzeLen = frameCount / 2

        guard analyzeLen > maxPeriod else { return buffer }

        // Compute autocorrelation for pitch detection
        var bestPeriod = maxPeriod
        var bestCorr: Float = -1

        for period in minPeriod...maxPeriod {
            var corr: Float = 0
            var count: Float = 0
            for i in analyzeStart..<(analyzeStart + analyzeLen - period) {
                corr += data[i] * data[i + period]
                count += 1
            }
            corr /= max(count, 1)
            if corr > bestCorr {
                bestCorr = corr
                bestPeriod = period
            }
        }

        let detectedFreq = sampleRate / Float(bestPeriod)

        // Human voice fundamental typically 85-255 Hz (adults)
        // If detected is outside this range, estimate shift factor
        let normalVoiceRange: ClosedRange<Float> = 85...255

        var shiftRatio: Float = 1.0
        if detectedFreq > normalVoiceRange.upperBound {
            // Pitch shifted up — bring it down
            shiftRatio = normalVoiceRange.upperBound / detectedFreq
        } else if detectedFreq < normalVoiceRange.lowerBound && detectedFreq > 20 {
            // Pitch shifted down — bring it up
            shiftRatio = normalVoiceRange.lowerBound / detectedFreq
        }

        // Clamp ratio
        shiftRatio = min(2.0, max(0.5, shiftRatio))

        // If ratio is near 1.0, no correction needed
        if abs(shiftRatio - 1.0) < 0.05 { return buffer }

        // Resample to correct pitch
        let newFrameCount = Int(Float(frameCount) / shiftRatio)
        let outputData = UnsafeMutablePointer<Float>.allocate(capacity: newFrameCount)
        outputData.initialize(repeating: 0, count: newFrameCount)
        defer { outputData.deallocate() }

        // Simple linear interpolation resampling
        for i in 0..<newFrameCount {
            let srcPos = Float(i) * shiftRatio
            let srcIdx = Int(srcPos)
            let frac = srcPos - Float(srcIdx)

            if srcIdx + 1 < frameCount {
                outputData[i] = data[srcIdx] * (1 - frac) + data[srcIdx + 1] * frac
            } else if srcIdx < frameCount {
                outputData[i] = data[srcIdx]
            }
        }

        let outBuffer = cloneBuffer(buffer, with: outputData, frameCount: newFrameCount)
        return outBuffer
    }

    // MARK: - Helpers

    private func cloneBuffer(_ buffer: AVAudioPCMBuffer, with data: UnsafePointer<Float>, frameCount: Int) -> AVAudioPCMBuffer {
        guard let newBuffer = AVAudioPCMBuffer(
            pcmFormat: buffer.format,
            frameCapacity: AVAudioFrameCount(frameCount)
        ) else {
            return buffer
        }
        newBuffer.frameLength = AVAudioFrameCount(frameCount)
        if let dst = newBuffer.floatChannelData?[0] {
            dst.update(from: data, count: frameCount)
        }
        return newBuffer
    }

    // MARK: - Export

    private func exportBuffers(
        _ buffers: [AVAudioPCMBuffer],
        format: AVAudioFormat
    ) async throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let outputURL = tempDir.appendingPathComponent("uncloaked_\(UUID().uuidString.prefix(8)).wav")

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
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
            throw AudioProcessorError.exportFailed("无法创建输出文件")
        }

        // If mono source, write mono output
        // If multi-channel, interleave
        if buffers.count == 1 {
            try outputFile.write(from: buffers[0])
        } else {
            // Create interleaved buffer
            let maxFrames = buffers.map { Int($0.frameLength) }.max() ?? 0
            guard let interleaved = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(maxFrames)
            ) else {
                throw AudioProcessorError.exportFailed("无法创建交织缓冲区")
            }
            interleaved.frameLength = AVAudioFrameCount(maxFrames)
            for ch in 0..<buffers.count {
                let src = buffers[ch]
                if let srcData = src.floatChannelData?[0],
                   let dstData = interleaved.floatChannelData?[ch] {
                    dstData.update(from: srcData, count: min(Int(src.frameLength), maxFrames))
                }
            }
            try outputFile.write(from: interleaved)
        }

        return outputURL
    }
}
