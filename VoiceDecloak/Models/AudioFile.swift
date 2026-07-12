import Foundation

/// Represents an audio file loaded for processing
struct AudioFile: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let name: String
    let duration: TimeInterval
    let sampleRate: Double
    let channelCount: Int

    var displayDuration: String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    static func == (lhs: AudioFile, rhs: AudioFile) -> Bool {
        lhs.id == rhs.id
    }
}

/// Processing techniques available to the user
enum ProcessingTechnique: String, CaseIterable, Identifiable {
    case noiseReduction = "降噪"
    case dereverberation = "去混响"
    case eqNormalization = "EQ 展平"
    case pitchCorrection = "基频还原"
    case speechEnhancement = "语音增强 (ML)"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .noiseReduction:     return "waveform"
        case .dereverberation:    return "dot.radiowaves.left.and.right"
        case .eqNormalization:    return "slider.horizontal.3"
        case .pitchCorrection:    return "guitars"
        case .speechEnhancement:  return "brain.head.profile"
        }
    }

    var description: String {
        switch self {
        case .noiseReduction:
            return "移除背景噪音和稳态噪声"
        case .dereverberation:
            return "消除房间混响和回声"
        case .eqNormalization:
            return "展平人工 EQ 滤波，恢复自然频谱"
        case .pitchCorrection:
            return "检测并逆转人工变调"
        case .speechEnhancement:
            return "使用机器学习模型增强语音"
        }
    }
}

/// Processing state
enum ProcessingState: Equatable {
    case idle
    case loading
    case processing(progress: Double, currentStep: String)
    case completed(outputURL: URL)
    case error(message: String)

    var isProcessing: Bool {
        if case .processing = self { return true }
        return false
    }
}

/// Configuration for the processing pipeline
struct ProcessingConfig {
    var enableNoiseReduction: Bool = true
    var enableDereverberation: Bool = true
    var enableEQNormalization: Bool = true
    var enablePitchCorrection: Bool = false
    var enableSpeechEnhancement: Bool = false

    var noiseReductionAmount: Float = 0.5   // 0.0 - 1.0
    var dereverbAmount: Float = 0.4
    var eqStrength: Float = 0.6
    var pitchTolerance: Float = 200.0        // Hz tolerance for pitch detection
}
