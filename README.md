# UtterLeaf · 言叶

把口述变成可以直接输入的文字。面向 macOS 的个人语音输入工具，对标 Typeless 的日常听写体验，允许自由选择语音识别与文字整理模型，并清楚展示使用量和成本。

## 当前状态

2026-10-23：原生 SwiftUI + AppKit MVP 已实现并编译为 macOS App。三条 ASR 管线和 v6 整理通过短合成内容 API 冒烟测试；完整的真实麦克风与原应用回填验收状态见实施记录。尚未签发正式开发者版本或发布。

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

## 构建与运行

需要 macOS 14+ 和完整 Xcode/Swift 工具链。本机验证环境：macOS 26.6.2 arm64、Xcode 26.4.1、Swift 6.3.1。没有第三方运行时或 Python 服务。

```sh
./scripts/test.sh
./scripts/build-app.sh
open .local/UtterLeaf.app
```

App 位于本项目 `.local/UtterLeaf.app`，源代码在 `Sources/`。Swift 编译缓存留在本项目 `.local/`，避免受保护的用户级缓存路径。`--disable-sandbox` 仅是 SwiftPM 清单构建参数，不代表 App 获得 macOS 隐私权限。

## 首次试用

1. 在「模型与设置」选择一条 ASR 试用管线。新安装不预设 ASR；试用选择可以随时更改。
2. 个人凭证从 Keychain 服务 `network.utterleaf.personal`（account 为变量名）或权限为 600 的 `~/.llm.env` 读取，语音调用只读取 `DOUBAO_API_KEY` 和 `DEEPSEEK_API_KEY`；账单同步额外允许 `UTTERLEAF_VOLC_ACCESS_KEY_ID` / `UTTERLEAF_VOLC_SECRET_ACCESS_KEY`。GUI 会自行读取文件，不依赖 shell export。不要把凭证放进本项目。
3. 第一次录音触发麦克风授权。Fn 全局监听和回填需要在系统设置中为当前 UtterLeaf 构建开启辅助功能。授权后监听会自动重试。
4. 在目标输入框按 **Fn** 并松开后开始，再单按一次结束。Fn + 方向键等组合键不会触发录音；Fn 本身的系统动作在监听期间被拦截，不修改系统键盘设置。整理结束后默认自动输入到原输入框；不按 Return、不发送消息。目标应用、输入框或光标发生变化时保留文字供处理。设置中可切换为先预览；保留稿可通过“输入到原应用”手动重试。
5. 本地历史保存原始转写与最终稿，直到手动清除；可改为只存最终稿或只存用量。录音只在内存中，单次上限 2 分钟。

**词汇表**：左侧一级入口支持添加、编辑、停用、删除与搜索。预置 Typeless / Typeface 语音输入软件语境纠错。词条仅作为整理上下文发送给个人 DeepSeek API，原始 ASR 不做全局替换；每次任务固定词汇表版本，回执记录其 hash。关闭整理时不应用词汇表。

**外观**：首次打开默认深色，可切换浅色/跟随系统。默认字号整体提高约 18%，常用选择统一为带滑动指示块的分段控件；减少动态效果时停用滑动。侧栏和自定义按钮有手形光标与浅色悬停反馈。品牌采用用户选定的叶片、对话气泡与声线组合；矢量与应用图标在 `assets/brand/`，设计说明在 [品牌记录](docs/6x23-brand-notes.md)。

**费用**：新的豆包与 DeepSeek 估算均按人民币显示，4 位小数。端到端合计按业务任务去重音频时长，同时有供应商/模型拆分。DeepSeek 初始使用 2026-10-23 官方人民币高峰参考价；非高峰需相应调整设置。失败/取消/中断调用若有已发送音频时长或 token 回执，也按原计价快照估算；缺少用量依据时仍保留未知。实际逐次金额需要能够对应的供应商账单。历史计价快照不会随设置变化而改写。

**本地数据**：`~/Library/Application Support/UtterLeaf/ledger.json`（目录 700、文件 600）。包含私人文本，请勿提交、公开或放进公共截图。App 不主动云同步；本地权限不是磁盘加密。清除正文保留字符计数与用量回执，不承诺清除供应商端或系统备份中的副本。

**开发版签名**：本机当前使用用户个人 Apple Development 身份签署，并启用 Hardened Runtime 与 audio-input entitlement。身份引用保存在 Git 忽略的 `.local/signing-identity`，也可用 `UTTERLEAF_SIGNING_IDENTITY` 指定；未配置的其他机器回退到 ad-hoc。旧 ad-hoc 授权可能需要移除旧条目并重新添加；同一开发者身份的后续构建拥有稳定 designated requirement。没有导出私钥或使用公司签名。正式分发仍需 Developer ID、公证和更新流程。

## 实施与验证

- [实施记录](docs/6x23-implementation-status.md) / [自动输入与词汇表更新](docs/6x23-autoinput-vocabulary-waveform.md)
- [视觉规范](DESIGN.md) / [交互约定](UX-CONTRACT.md)
- `Tests/UtterLeafCoreTests/`：协议、封装、费用、持久化和权限失败边界的自动测试。
- `.local/verification/`：本机测试、构建、短 API 冒烟回执；不包含凭证或历史私人录音。

不自动重跑 `research/benchmark` 的完整历史研究。短 API 冒烟测试只使用合成内容，且不进入用户账本。

## 后续路线

- **Phase 1**：打磨私人语音输入、Fn、回填与稳定性。
- **Phase 2**：类似 Granola 的长时会议转录与笔记，包含说话人、时间戳、整理转录和 brief。
- **后续扩展**：连接 Slack，按配置自动发送整理转录与 brief，并显示发送结果。

产品范围见 [分阶段需求](docs/6x23-product-brief.md)；当前会议与 Slack 功能尚未实现。

## 实时波形

参考 MIT [SpeechWaveAnimation](https://github.com/mvolpato/SpeechWaveAnimation) 的正弦声线与抛物线包络，自行适配为 SwiftUI Canvas 三层连续声线。没有外部 Swift 包依赖；复用同一录音回调 RMS，不额外录音、不做 FFT。录音时局部绘制目标 30fps；转写、整理与输入阶段移除整个波形，仅保留状态与进度。Reduce Motion 使用无相位运动的低频更新。许可随 App 附带。

## 表达额度

用量页顶部显示滚动 7 天 / 30 天预算，初始 CNY 5 / 20，可在“调整预算”修改。绿条代表剩余额度，仅作本地提醒，不限制录音，不代表供应商余额。按已知估算扣减，未知金额单独提示；完整听写样本用于估算预算可写字数。每个周期显示豆包 / DeepSeek 已知估算成本占比与比值。逐次调用移到“查看明细”弹窗，独立滚动并可查看回执；每千字与每小时成本统一放在主页面底部。

Fn 开始后可按 Esc 取消录音或尚未完成的转写/整理；已开始输入时不取消，以免中断写入。

## 官方核对与自动同步

App 运行时每 20 分钟查询，启动/唤醒后检查是否到期，正在听写时延后自动查询。可关闭自动同步，也可“立即核对”。查询使用独立的短时 URLSession；不上传录音、转写或 Prompt，不依赖后台服务或新 SDK。退出后不继续查询，也不唤醒睡眠中的电脑。

- **DeepSeek**：通过官方 `GET /user/balance` 保存账户余额快照。余额不是逐笔账单；充值、赠金或其他应用消费不会被分配成 UtterLeaf 费用。
- **豆包**：通过火山 `ListBillDetail` 查询最近 30 天的账单，需在同步设置填写费用中心的实例 ID（不一定等于语音 App ID），产品代码可选。本机 Keychain（服务 `network.utterleaf.personal`）或 `~/.llm.env` 需配置 `UTTERLEAF_VOLC_ACCESS_KEY_ID` 与 `UTTERLEAF_VOLC_SECRET_ACCESS_KEY`，建议个人 IAM 子用户的账单只读凭证。App 不显示密钥，文件权限需为 600。
- 账单按明细 ID 去重，完整翻页后原子替换对应快照；范围不符、字段缺失、页数异常或网络失败时保留上次成功数据。小时账单可能延迟数小时，空结果不代表免费。
- 官方应付金额以实例汇总单列。只有用户确认实例专用于 UtterLeaf 时才显示与本地同账单区间的估算差额；汇总金额不自动摊到逐次调用，不覆盖手工核对。

配置步骤：个人火山控制台 → IAM 账单只读子用户 → 创建 AK/SK → 在本机保存上述变量 → 费用中心找到豆包语音账单的 InstanceNo → UtterLeaf 同步设置填写 → 立即核对。不要把密钥发送到聊天或提交到仓库。

## 窗口与录音胶囊动画

双击窗口顶部空白区域，在当前桌面铺满菜单栏与 Dock 之间的可用屏幕；再双击恢复先前的位置和尺寸。不会新建全屏桌面。窗口按钮和模态编辑区域保留原有操作。

Fn 开始时胶囊从底部轻轻展开；结束录音后声线淡出，胶囊收窄成处理中；完成后短暂显示真实结果，再缩小淡出。取消、文字保留和输入成功分别展示，不把未确认粘贴显示为成功。动画不会延迟 API 或回填，快速重录会取消旧退场任务。启用系统“减少动态效果”时仅短暂淡入淡出。浮层不激活窗口、不占键盘焦点；退场不拦截鼠标。

输入框采用统一圆角绿系外观，保留系统编辑和输入法；额度卡合并成本构成到近 30 天页脚，缺回执少于 5 次时隐藏额度提示（明细仍保留）。声线显示增益 1.7×、近静音 -50dB 门限，胶囊尺寸不变。

提示音默认 A · 轻触，在“模型与设置 → 提示音”可切换 B · 木滴 / C · 清铃、调音量、静音或试听。三组原创 WAV 随 App 打包，播放不联网。开始音结束后开启采音，结束音在停止采音后播放；只有确认回填成功才播放完成音。

文字整理固定追加 `arabic-digits-v1` 数字偏好：明确的英文编号优先使用阿拉伯数字，如 session one/two → session 1/2、队名 G two → G2；保护 OneDrive、OnePlus、Formula One 等固定名称及明确引用的原样字符串。v6 原文件和 JSON 数据封装保留，实际复合 Prompt 的 hash 与版本写入调用/任务回执。

额度进度同时显示本周期“已写 X 字”：按 7 天 / 30 天内听写任务的最终稿字符计数，含标点与空白，同次听写只算一次；不因两家 API 或整理重试重复累计，清除正文后仍保留计数。
