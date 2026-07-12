import Foundation
import Combine
import AVFoundation

@MainActor
final class ProcessingViewModel: ObservableObject {
    @Published var state: ProcessingState = .idle
    @Published var inputFile: AudioFile?
    @Published var config = ProcessingConfig()
    @Published var enabledTechniques: Set<ProcessingTechnique> = [.noiseReduction, .dereverberation, .eqNormalization]

    private let processor = AudioProcessor()
    private let restorer = VoiceRestorer()

    func loadAudio(from url: URL) async {
        state = .loading
        do {
            let asset = AVAsset(url: url)
            let duration = try await asset.load(.duration)
            let durationSeconds = CMTimeGetSeconds(duration)

            guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
                state = .error(message: "未检测到音频轨道")
                return
            }
            let desc = try await track.load(.formatDescriptions).first
            let basicDesc = CMAudioFormatDescriptionGetStreamBasicDescription(desc as! CMAudioFormatDescription)!.pointee

            let file = AudioFile(
                url: url,
                name: url.lastPathComponent,
                duration: durationSeconds,
                sampleRate: basicDesc.mSampleRate,
                channelCount: Int(basicDesc.mChannelsPerFrame)
            )
            inputFile = file
            state = .idle
        } catch {
            state = .error(message: "加载音频失败: \(error.localizedDescription)")
        }
    }

    func process() async {
        guard let inputFile else {
            state = .error(message: "请先选择音频文件")
            return
        }

        state = .processing(progress: 0.0, currentStep: "准备处理...")

        // Apply config from enabled techniques
        config.enableNoiseReduction = enabledTechniques.contains(.noiseReduction)
        config.enableDereverberation = enabledTechniques.contains(.dereverberation)
        config.enableEQNormalization = enabledTechniques.contains(.eqNormalization)
        config.enablePitchCorrection = enabledTechniques.contains(.pitchCorrection)
        config.enableSpeechEnhancement = enabledTechniques.contains(.speechEnhancement)

        do {
            let outputURL = try await processor.process(
                inputURL: inputFile.url,
                config: config,
                progressHandler: { [weak self] progress, step in
                    self?.state = .processing(progress: progress, currentStep: step)
                }
            )

            // Apply ML-based enhancement if enabled
            var finalURL = outputURL
            if config.enableSpeechEnhancement {
                self.state = .processing(progress: 0.85, currentStep: "ML 语音增强...")
                finalURL = try await restorer.enhance(url: outputURL)
            }

            state = .completed(outputURL: finalURL)
        } catch {
            state = .error(message: "处理失败: \(error.localizedDescription)")
        }
    }

    func reset() {
        state = .idle
        inputFile = nil
    }
}
