# UtterLeaf · 言叶

把口述变成可以直接输入的文字。面向 macOS 的个人语音输入工具，对标 Typeless 的日常听写体验，允许自由选择语音识别与文字整理模型，并清楚展示使用量和成本。

## 当前状态

2026-10-23：项目交接资料已准备。已有真实录音评测和可复用 prompt；尚未实现、编译或发布 App。

项目目录：`/Users/wangyifan/Desktop/Research/Sessions/6x-UtterLeaf`，保留在 Sessions 下，与 Reverse Anything 调研目录分开组织。UtterLeaf 是用户选定的工作名，尚未作商标、域名或商店名称核验。

## 新会话从这里开始

1. 阅读 [AGENTS.md](AGENTS.md)。
2. 阅读 [.codex/handoff/6x23-handoff-utterleaf.md](.codex/handoff/6x23-handoff-utterleaf.md)。
3. 阅读 [产品需求](docs/6x23-product-brief.md) 和 [技术与评测交接](docs/6x23-technical-handoff.md)。
4. 使用 [新会话开场说明](docs/6x23-start-new-session.md) 在这个目录启动新的 Codex 会话。

## 已确认的方向

- 用户认为这轮豆包转写 + DeepSeek Flash 整理的效果大多已满足需求。
- 暂不锁死某个转写模型，三条已验证管线作为可选项，在 App 实际试用中决定默认值。
- 文字整理先使用 DeepSeek Flash；prompt 应能版本化、编辑和回滚。
- 需要查看各 API 的使用量、实际或估算费用、每千字和每小时成本。
- 需要支持口述符号：例如 `tap on 杠 31` → `tap on-31`；同时避免改坏“讨论括号、引号”这样的普通文字。
- 私人录音和文字不使用公司的 OpenRouter Key。

## 资料结构

```text
AGENTS.md
docs/                         产品需求、技术交接、新会话开场说明
prompts/                      可迁移的 system prompt 与调用封装说明
research/benchmark/           实验脚本、依赖、汇总指标和合成回归记录
.codex/handoff/               当前私人工作交接，Git 忽略
```

完整的原始录音、Typeless 对照和请求回执仍留在：

`/Users/wangyifan/Desktop/Research/Sessions/6x-SpeechToTextBenchmark`

这里只迁移实验代码、prompt、汇总指标与合成回归数据，不复制数据库、私人音频、私人全文或任何密钥。

## 下一阶段

建议先实现 macOS 最小闭环：快捷键录音 → 可选 ASR → DeepSeek Flash 整理 → 用户确认/插入文字 → 本地使用量记录。技术栈尚未正式锁定；优先评估 SwiftUI + 原生音频/辅助功能接口，并在实现前核实本机工具链和系统权限行为。
