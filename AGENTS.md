# voice-uncloak

Voice Uncloak (声纹剥离) A voice restoration and enhancement app that removes background noise, reverberation, and restores speech clarity using DSP and ML. Features - Noise reduction - Dereverberation - EQ normalization - Pitch correction

## 用途与 Target 判定

声纹/语音相关 AI 工具

- 移动端：可选
- 智能硬件：不适用

## 目标平台

| 平台 | 方式 | 产出 |
|------|------|------|
| 移动端 | 可选 | — |

## 命令

```bash
# 见 README；归档工程以只读/小修为主
```

## 状态

已归档。默认只做必要修复与知识库同步，不新开大范围需求。

## 助手约束

- Loop：先定可验证 Done 与停止条件；每切片过验证环；失败回灌；详见 docs/LOOP_ENGINEERING.md
- Harness：遵循根 AGENTS「Harness Engineering」；Guide=本文件，Sensor=测试/CI；同类失误二次须沉淀规则或测试（棘轮）。详见 docs/HARNESS_ENGINEERING.md
- 遵循仓库根 `/Users/skat/AGENTS.md` 与本文件的用途判定
- 可选 Target 可搁置；不适用形态不要硬加
- 改动聚焦；公共逻辑抽离复用
