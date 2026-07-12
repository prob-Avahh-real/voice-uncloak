import SwiftUI
import Accelerate

/// Renders a waveform visualization from audio sample data.
/// Supports both raw float data for preview and overlay display.
struct WaveformView: View {
    let samples: [Float]
    let color: Color

    init(samples: [Float], color: Color = .cyan) {
        self.samples = samples
        self.color = color
    }

    /// Downsample to `targetPoints` for display
    private var displaySamples: [Float] {
        guard !samples.isEmpty else { return [] }
        let targetCount = min(200, samples.count)
        let stride = max(1, samples.count / targetCount)
        var result: [Float] = []
        for i in 0..<targetCount {
            let rangeStart = i * stride
            let rangeEnd = min(rangeStart + stride, samples.count)
            var maxVal: Float = 0
            for j in rangeStart..<rangeEnd {
                maxVal = Swift.max(maxVal, abs(samples[j]))
            }
            result.append(maxVal)
        }
        return result
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let midY = height / 2
            let points = displaySamples

            Path { path in
                guard !points.isEmpty else { return }
                let stepX = width / CGFloat(points.count)

                // Top half
                path.move(to: CGPoint(x: 0, y: midY))
                for (i, sample) in points.enumerated() {
                    let x = stepX * CGFloat(i)
                    let y = midY - CGFloat(sample) * midY
                    path.addLine(to: CGPoint(x: x, y: y))
                }

                // Bottom half (mirrored)
                for (i, sample) in points.enumerated().reversed() {
                    let x = stepX * CGFloat(i)
                    let y = midY + CGFloat(sample) * midY
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                path.closeSubpath()
            }
            .fill(
                LinearGradient(
                    colors: [color.opacity(0.6), color.opacity(0.2)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }
}

// MARK: - Animated Waveform (for processing indication)

struct AnimatedWaveformView: View {
    @State private var phase: Double = 0

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let width = size.width
                let height = size.height
                let midY = height / 2
                let barCount = 30
                let barWidth = width / CGFloat(barCount)

                for i in 0..<barCount {
                    let x = barWidth * CGFloat(i) + barWidth * 0.2
                    let phaseOffset = Double(i) * 0.3
                    let value = sin(timeline.date.timeIntervalSince1970 * 4 + phaseOffset)
                    let amplitude = abs(value) * midY * 0.7 + midY * 0.1

                    let rect = CGRect(
                        x: x,
                        y: midY - amplitude,
                        width: barWidth * 0.6,
                        height: amplitude * 2
                    )

                    context.fill(
                        Path(roundedRect: rect, cornerRadius: barWidth * 0.2),
                        with: .color(.cyan.opacity(0.4 + abs(value) * 0.3))
                    )
                }
            }
        }
    }
}

#Preview("Waveform") {
    let samples: [Float] = (0..<1000).map { i in
        let t = Float(i) / 100
        return sin(t * 2 * .pi * 3) * exp(-t / 20) + Float.random(in: -0.05...0.05)
    }

    WaveformView(samples: samples)
        .frame(height: 100)
        .padding()
        .background(Color.black)
        .preferredColorScheme(.dark)
}

#Preview("Animated") {
    AnimatedWaveformView()
        .frame(height: 80)
        .padding()
        .background(Color.black)
        .preferredColorScheme(.dark)
}
