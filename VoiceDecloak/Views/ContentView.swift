import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var viewModel: ProcessingViewModel
    @State private var showFileImporter = false
    @State private var showSettings = false
    @State private var audioPlayer: AVAudioPlayer?

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    headerSection
                    fileSection
                    techniquesSection
                    actionSection
                    Spacer(minLength: 20)
                }
            }
            .navigationTitle("声纹还原")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.audio, .wav, .mp3, .mpeg4Audio]
            ) { result in
                switch result {
                case .success(let url):
                    let secured = url.startAccessingSecurityScopedResource()
                    Task { await viewModel.loadAudio(from: url) }
                    // Release after a delay to allow reading
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        if secured { url.stopAccessingSecurityScopedResource() }
                    }
                case .failure(let error):
                    viewModel.state = .error(message: error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.cyan, .blue.opacity(0.3))
                .padding(.top, 20)

            Text("反向还原加工过的声音")
                .font(.title3.weight(.medium))

            Text("去除人工声纹，恢复原声")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.bottom, 20)
    }

    // MARK: - File Section

    private var fileSection: some View {
        VStack(spacing: 12) {
            if let file = viewModel.inputFile {
                // Loaded file info
                HStack {
                    Image(systemName: "waveform")
                        .foregroundColor(.cyan)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.name)
                            .font(.headline)
                            .lineLimit(1)
                        Text("\(file.displayDuration)  •  \(Int(file.sampleRate/1000))kHz  •  \(file.channelCount)ch")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button {
                        playAudio(url: file.url)
                    } label: {
                        Image(systemName: "play.circle.fill")
                            .font(.title2)
                            .foregroundColor(.cyan)
                    }
                    Button {
                        viewModel.reset()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.gray)
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
            } else {
                // Empty state
                Button {
                    showFileImporter = true
                } label: {
                    VStack(spacing: 12) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.cyan)
                        Text("选择音频文件")
                            .font(.headline)
                        Text("支持 WAV, MP3, M4A 等格式")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Techniques

    private var techniquesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("处理方式")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal)
                .padding(.top, 20)

            ForEach(ProcessingTechnique.allCases) { technique in
                TechniqueRow(
                    technique: technique,
                    isEnabled: viewModel.enabledTechniques.contains(technique)
                ) {
                    if viewModel.enabledTechniques.contains(technique) {
                        viewModel.enabledTechniques.remove(technique)
                    } else {
                        viewModel.enabledTechniques.insert(technique)
                    }
                }
            }

            if viewModel.enabledTechniques.contains(.pitchCorrection) {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.orange)
                    Text("基频还原为实验性功能，处理时间较长")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Action

    private var actionSection: some View {
        VStack(spacing: 12) {
            // State indicator
            switch viewModel.state {
            case .idle:
                if viewModel.inputFile != nil {
                    Button {
                        Task { await viewModel.process() }
                    } label: {
                        Label("开始剥离声纹", systemImage: "scissors")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.cyan)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .font(.headline)
                    }
                }

            case .loading:
                HStack {
                    ProgressView()
                    Text("加载中...")
                        .foregroundColor(.secondary)
                }

            case .processing(let progress, let step):
                VStack(spacing: 8) {
                    ProgressView(value: progress)
                        .tint(.cyan)
                    Text(step)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(Int(progress * 100))%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding()

            case .completed(let url):
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.green)
                    Text("处理完成")
                        .font(.headline)

                    HStack(spacing: 16) {
                        Button {
                            playAudio(url: url)
                        } label: {
                            Label("试听", systemImage: "play.circle")
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(Color.cyan.opacity(0.15))
                                .foregroundColor(.cyan)
                                .clipShape(Capsule())
                        }

                        Button {
                            shareAudio(url: url)
                        } label: {
                            Label("分享", systemImage: "square.and.arrow.up")
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(Color.blue.opacity(0.15))
                                .foregroundColor(.blue)
                                .clipShape(Capsule())
                        }
                    }

                    Button {
                        viewModel.reset()
                    } label: {
                        Text("重新开始")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()

            case .error(let msg):
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.orange)
                    Text(msg)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("重试") {
                        viewModel.state = .idle
                    }
                    .font(.caption)
                }
                .padding()
            }

            if case .idle = viewModel.state {} else if case .completed = viewModel.state {} else {
                // Show cancel during processing
                if viewModel.state.isProcessing {
                    Button("取消") {
                        viewModel.reset()
                    }
                    .font(.caption)
                    .foregroundColor(.red)
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 20)
    }

    // MARK: - Helpers

    private func playAudio(url: URL) {
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
        } catch {
            viewModel.state = .error(message: "播放失败: \(error.localizedDescription)")
        }
    }

    private func shareAudio(url: URL) {
        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(av, animated: true)
        }
    }
}

// MARK: - Technique Row

struct TechniqueRow: View {
    let technique: ProcessingTechnique
    let isEnabled: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 14) {
                Image(systemName: technique.symbol)
                    .font(.title3)
                    .foregroundColor(isEnabled ? .cyan : .gray)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(technique.rawValue)
                        .font(.body.weight(.medium))
                        .foregroundColor(.primary)
                    Text(technique.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Toggle("", isOn: .constant(isEnabled))
                    .labelsHidden()
                    .tint(.cyan)
                    .allowsHitTesting(false)
            }
            .padding()
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }
}

#Preview {
    ContentView()
        .environmentObject(ProcessingViewModel())
        .preferredColorScheme(.dark)
}
