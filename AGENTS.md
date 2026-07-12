# AGENTS.md — VoiceUncloak

声纹还原。5 步 DSP 管线：谱减法降噪 → 时变谱减法去混响 → 频谱包络均衡 → 自相关基频还原 → 频谱平滑+CoreML。全本地处理，零网络请求。SwiftUI + MVVM。

## 命令

```bash
make generate     # xcodegen generate
make open         # open *.xcodeproj
make build        # xcodebuild (simulator)
make test         # xcodebuild test
make clean        # 清理
```

## 架构

```
MVVM (SwiftUI + @ObservableObject)
  VoiceDecloak/
  ├── VoiceDecloakApp.swift              # @main entry
  ├── AudioEngine/
  │   └── AudioProcessor.swift           # 706行 DSP 管线
  ├── ML/
  │   └── SpeechEnhancer.swift           # VoiceRestorer (频谱平滑+CoreML插槽)
  ├── Models/
  │   └── AudioFile.swift                # 数据模型+ProcessingConfig+ProcessingState
  ├── ViewModels/
  │   └── ProcessingViewModel.swift      # 异步管线编排
  ├── Views/
  │   ├── ContentView.swift              # 主界面
  │   ├── SettingsView.swift             # 参数调节
  │   └── WaveformView.swift             # 波形可视化
  └── ABTesting/
      └── ABTest.swift                   # A/B实验框架
```

## 处理管线

```
Input WAV → STFT (Accelerate vDSP)
  → Step1: 谱减法降噪（5帧噪声估计+oversubtraction+Hann窗+overlap-add）
  → Step2: 时变谱减法去混响（3帧历史平均→估计混响尾音→保留直达声）
  → Step3: EQ展平（长期平均谱→逆滤波→gain clamp [0.1, 10.0]）
  → Step4: 自相关基频检测+线性插值重采样（50-400Hz范围→normal voice 85-255Hz）
  → Step5: 频谱平滑+CoreML插槽（邻域平均3点→待训练模型）
  → ISTFT → Output WAV
每步可选开关（ProcessingConfig）。
```

## 关键设计决策

- **全本地**：音频从未离开设备。Accelerate vDSP FFT，CoreML 在 Apple Neural Engine。
- **Pipeline Pattern**：5 步依次处理，每步可独立启用/禁用。`totalSteps` 仅计数已启用的步骤。
- **Progress Handler**：`(Double, String) -> Void` closure，每一步报告进度和步骤名。
- **双后端策略**：Step5 当前用频谱平滑（确定性），预留 `VoiceRestorer` 的 CoreML 插槽。
- **基频还原**：自相关检测主导频率 → 与正常语音范围（85-255Hz）比较 → 超出则线性插值重采样逆转。

## A/B 实验

5 个预设实验（`ABTest.Experiment`）：
- `pipelineUI`: vertical vs horizontal 布局
- `processingPreview`: livePreview 20% 流量
- `defaultConfig`: aggressive/conservative/balanced 三路
- `onboardingFlow`: guided/skipToAction
- `exportFormat`: wav(70%)/m4a(30%)

```swift
ABTest.initializeExperiments()
let variant = ABTest.variant(for: .pipelineUI, userId: user.id)
```

## 测试（810行 / 7种类型 / 50 case）

```
VoiceDecloakTests/
├── AudioProcessorUnitTests.swift    # 8 tests — 全管线/单步/进度/空配置/极短音频
├── ModelUnitTests.swift             # 14 tests — AudioFile/Technique/Config/State/Error
├── ViewModelUnitTests.swift         # 6 tests  — MVVM状态机/技术开关/无输入报错
├── VoiceRestorerUnitTests.swift     # 3 tests  — 增强/极短/48kHz保留
├── Resilience/ResilienceTests.swift # 7 tests  — 无效文件/目录/零参数/最大参数/并发
├── Performance/PerformanceBenchmarks.swift # 4 tests — 性能基准（XCTClock+CPU+Memory）
└── ABTesting/ABTestingTests.swift   # 8 tests  — 分流/精度/三路/fallback/指标
```

## 约定

- 处理结果导出为 32-bit float WAV，临时目录 `uncloaked_{uuid}.wav`。
- Error 枚举：`AudioProcessorError` 含中文 `errorDescription`。
- ProcessingState 用 `Equatable`，`isProcessing` 仅 `.processing` case 返回 true。
- 模型训练后替换 `VoiceRestorer.enhance()` 中的频谱平滑为 CoreML 推理。
