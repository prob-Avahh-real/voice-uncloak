import Foundation

/// 轻量 A/B 实验框架 — 零依赖
///
/// 用法：
/// ```swift
/// let variant = ABTest.variant(for: .ui_layout_v2)
/// if variant == .b {
///     showNewLayout()
/// }
/// ```
///
/// 不是选择，是约束。产品决策必须有数据支撑。
struct ABTest {
    let experimentKey: String
    let variants: [String]
    let trafficSplit: [Double]  // must sum to 1.0

    static var activeExperiments: [String: ABTest] = [:]

    /// 注册实验
    static func register(
        key: String,
        variants: [String],
        trafficSplit: [Double]
    ) {
        activeExperiments[key] = ABTest(
            experimentKey: key,
            variants: variants,
            trafficSplit: trafficSplit
        )
    }

    /// 获取当前用户的 variant — 基于稳定的用户 ID hash
    static func variant(for key: String, userId: String? = nil) -> String {
        guard let experiment = activeExperiments[key],
              experiment.variants.count == experiment.trafficSplit.count else {
            return "control"
        }

        let seed = userId ?? ProcessInfo.processInfo.globallyUniqueString
        let hash = abs(seed.hashValue) % 10000
        let percentile = Double(hash) / 10000.0

        var cumulative = 0.0
        for (i, split) in experiment.trafficSplit.enumerated() {
            cumulative += split
            if percentile < cumulative {
                return experiment.variants[i]
            }
        }
        return experiment.variants.last ?? "control"
    }

    /// 上报 variant 分配（Firebase Analytics / 自定义分析）
    static func trackExposure(experiment: String, variant: String) {
        // Integration point: Firebase Analytics, PostHog, etc.
        print("[ABTest] Exposure — \(experiment): \(variant)")
    }
}

// MARK: - VoiceUncloak Experiments

extension ABTest {
    /// 预定义的实验
    enum Experiment: String, CaseIterable {
        case pipelineUI = "pipeline_ui_v1"           // 管线 UI 布局
        case processingPreview = "preview_v1"        // 处理前/后实时预览
        case defaultConfig = "default_config_v1"     // 默认处理配置
        case onboardingFlow = "onboarding_v1"        // 引导流程
        case exportFormat = "export_format_v1"       // 导出格式默认值
    }

    /// 初始化所有 VoiceUncloak 实验
    static func initializeExperiments() {
        register(key: Experiment.pipelineUI.rawValue,
                 variants: ["vertical", "horizontal"],
                 trafficSplit: [0.5, 0.5])

        register(key: Experiment.processingPreview.rawValue,
                 variants: ["control", "livePreview"],
                 trafficSplit: [0.8, 0.2])  // 保守：20% 新功能

        register(key: Experiment.defaultConfig.rawValue,
                 variants: ["aggressive", "conservative", "balanced"],
                 trafficSplit: [0.33, 0.33, 0.34])

        register(key: Experiment.onboardingFlow.rawValue,
                 variants: ["control", "guided", "skipToAction"],
                 trafficSplit: [0.5, 0.3, 0.2])

        register(key: Experiment.exportFormat.rawValue,
                 variants: ["wav", "m4a"],
                 trafficSplit: [0.7, 0.3])
    }
}

// MARK: - AB Test Result Accumulator

/// 累积 A/B 测试结果的结构
struct ABTestMetrics {
    var exposures: [String: Int] = [:]
    var completions: [String: Int] = [:]
    var errors: [String: Int] = [:]

    /// 处理完成率
    func completionRate(for variant: String) -> Double {
        let exposed = Double(exposures[variant] ?? 1)
        let completed = Double(completions[variant] ?? 0)
        return completed / max(exposed, 1)
    }

    /// 错误率
    func errorRate(for variant: String) -> Double {
        let exposed = Double(exposures[variant] ?? 1)
        let errCount = Double(errors[variant] ?? 0)
        return errCount / max(exposed, 1)
    }
}
