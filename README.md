# Voice Uncloak (声纹剥离)

A voice restoration and enhancement app that removes background noise, reverberation, and restores speech clarity using DSP and ML.

## Features
- Noise reduction
- Dereverberation
- EQ normalization
- Pitch correction
- ML-based speech enhancement
- Performance benchmark suite
- A/B testing infrastructure

## Architecture
- MVVM pattern with ProcessingViewModel
- AudioProcessor DSP pipeline
- SpeechEnhancer ML module
- XCTest unit + performance + resilience tests

## Requirements
- iOS 17.0+
- Xcode 15.0+
- Microphone permission for recording

## Privacy
- All audio processing happens on-device
- No network requests or data collection
- Microphone usage is clearly explained in Info.plist
