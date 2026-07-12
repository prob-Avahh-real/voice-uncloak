import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var viewModel: ProcessingViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Noise Reduction
                if viewModel.enabledTechniques.contains(.noiseReduction) {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("降噪强度")
                                Spacer()
                                Text("\(Int(viewModel.config.noiseReductionAmount * 100))%")
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                            }
                            Slider(value: $viewModel.config.noiseReductionAmount, in: 0.0...1.0)
                                .tint(.cyan)
                            Text("较高强度可去除更多背景噪声，但可能影响语音清晰度")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } header: {
                        Label("降噪", systemImage: "waveform")
                    }
                }

                // MARK: - Dereverberation
                if viewModel.enabledTechniques.contains(.dereverberation) {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("去混响强度")
                                Spacer()
                                Text("\(Int(viewModel.config.dereverbAmount * 100))%")
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                            }
                            Slider(value: $viewModel.config.dereverbAmount, in: 0.0...1.0)
                                .tint(.cyan)
                            Text("减少房间反射声和人工混响效果")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } header: {
                        Label("去混响", systemImage: "dot.radiowaves.left.and.right")
                    }
                }

                // MARK: - EQ
                if viewModel.enabledTechniques.contains(.eqNormalization) {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("EQ 展平强度")
                                Spacer()
                                Text("\(Int(viewModel.config.eqStrength * 100))%")
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                            }
                            Slider(value: $viewModel.config.eqStrength, in: 0.0...1.0)
                                .tint(.cyan)
                            Text("展平人工频率响应，恢复自然音色")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } header: {
                        Label("EQ 展平", systemImage: "slider.horizontal.3")
                    }
                }

                // MARK: - Pitch
                if viewModel.enabledTechniques.contains(.pitchCorrection) {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("基频容差")
                                Spacer()
                                Text("\(Int(viewModel.config.pitchTolerance)) Hz")
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                            }
                            Slider(value: $viewModel.config.pitchTolerance, in: 50...500)
                                .tint(.cyan)
                            Text("检测到人工变调后，将基频还原到正常语音范围 (85-255 Hz)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } header: {
                        Label("基频还原", systemImage: "guitars")
                    } footer: {
                        Text("⚠️ 实验性功能：仅适用于简单变调，对 AI 变声效果有限")
                    }
                }

                // MARK: - ML Enhancement
                if viewModel.enabledTechniques.contains(.speechEnhancement) {
                    Section {
                        HStack {
                            Image(systemName: "brain.head.profile")
                                .foregroundColor(.cyan)
                            Text("使用频谱平滑算法减少残留artifact")
                                .font(.subheadline)
                        }
                        Text("CoreML 模型版本将在后续更新中提供")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } header: {
                        Label("语音增强 (ML)", systemImage: "brain.head.profile")
                    }
                }

                // MARK: - About
                Section {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("处理引擎")
                        Spacer()
                        Text("Accelerate vDSP FFT")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Label("关于", systemImage: "info.circle")
                }
            }
            .navigationTitle("处理参数")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(ProcessingViewModel())
        .preferredColorScheme(.dark)
}
