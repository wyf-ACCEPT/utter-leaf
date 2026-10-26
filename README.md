<p align="center">
  <img src="assets/brand/utterleaf-app-icon.png" width="112" alt="UtterLeaf app icon">
</p>

<h1 align="center">UtterLeaf · 言叶</h1>

<p align="center">Speak naturally. Keep your words.</p>
<p align="center"><a href="#english">English</a> · <a href="#中文">中文</a></p>

## English

UtterLeaf is a personal macOS dictation app inspired by Typeless. Press **Fn**, speak, then press **Fn** again: Doubao transcribes your speech, DeepSeek tidies it up, and UtterLeaf inserts the result into the original input field.

Built with **SwiftUI, AppKit, AVAudioEngine and URLSession**, with no third-party runtime service. The current app interface is in Chinese; this README is bilingual.

### Status

**Working personal development build — October 26, 2026.** macOS dictation is implemented, with ongoing reliability work. This repository does not provide a notarized release, an installer, or a hosted API service. An initial meeting-transcription workflow is now implemented; iOS remains planned.

The latest local suite passes **89 tests**. Short synthetic API checks and real microphone/insertion trials have been performed. Intermittent Codex target-capture failures remain under investigation; the latest capture retry needs further user testing. A full five-minute live recording has not yet been validated. Tests and successful builds do not establish compatibility with every input field.

### Features

- **Fn to start/stop; Esc to cancel** recording or pending processing. Fn combinations pass through. UtterLeaf never presses Return or sends your message.
- **Up to five minutes per dictation.** The capsule shows a countdown during the last 30 seconds, then stops recording and processes the captured audio.
- **Three selectable Doubao ASR routes:** streaming with results after recording, live streaming, and file transcription. No route is preselected on a fresh install.
- **Optional DeepSeek Flash cleanup:** removes disfluencies, preserves meaning, converts spoken symbols, and favors digits in numbered English expressions such as `session one → session 1`. Transcript data is JSON-wrapped and treated as data, not executable instructions.
- **Contextual vocabulary** for names, preferred spellings and commonly confused terms, rather than unconditional replacement.
- **Guarded automatic insertion**, with an optional preview mode. If the target app, field or caret changes, the text is retained for recovery. Clipboard paste is used where appropriate; insertion is verified where the target exposes enough information.
- **Local history** with configurable text retention, plus usage counts, CNY cost estimates, provider cost shares, and rolling 7/30-day budget indicators. Budgets are reminders, not usage limits or provider balances.
- **Dark mode by default**, light/system themes, a lightweight audio-reactive capsule, reduced-motion support and three bundled sound sets.

### Build and run

Requirements: **macOS 14+** and an Xcode/Swift toolchain supporting the package's **Swift tools 6.0** manifest. No Python service or Node runtime is needed to run the app.

```sh
git clone https://github.com/wyf-ACCEPT/utter-leaf.git
cd utter-leaf
./scripts/test.sh
./scripts/build-app.sh
open .local/UtterLeaf.app
```

The build script stages and signs the bundle, verifies it, then replaces the installed bundle by rename. Build artifacts and caches stay local and are ignored by Git. By default, other machines use ad-hoc signing. You can supply your own identity through `UTTERLEAF_SIGNING_IDENTITY`; the optional `.local/signing-identity` file is also ignored. Rebuilding with ad-hoc signing may require renewing macOS permission grants. Developer ID signing and notarization are not included.

### Personal setup

1. Configure your own `DOUBAO_API_KEY` and `DEEPSEEK_API_KEY`. The app reads macOS Keychain service `network.utterleaf.personal`, using the variable name as the account, or falls back to `~/.llm.env` with permissions set to `600`. It reads that file directly; shell exports are not required. **No provider key is bundled with the app.** Do not commit credentials.
2. In **模型与设置** (Models & Settings), select an ASR route and whether to enable cleanup.
3. Grant **Microphone** permission for recording and **Accessibility** permission for Fn handling and insertion.
4. Click your destination input field, press and release **Fn**, speak, then press and release **Fn** again. Keep the original field and caret unchanged while processing. Use **Esc** to cancel before insertion begins.

The file route preserves an experimentally verified `audio.data` submission path. This path is not explicitly listed in the referenced official file-ASR schema; use a streaming route if compatibility fails.

### Meetings (Phase 2 preview)

The **会议** page records microphone audio with optional system audio, supports pause/resume and local notes, and retains recordings on disk for playback or explicit deletion. Sessions are separate from five-minute dictation and currently cap at three hours. Optional live captions incur separate streaming calls; their speaker labels are provisional. After recording, whole-session ASR produces timestamped speaker turns, with independent cleaned transcript and source-referenced Brief generation.

Cloud voiceprint identities can be refreshed, enabled, renamed or soft-deleted. Registration currently requires a user-provided HTTPS signed URL for a 5–30 second single-speaker sample; there is no automatic local-sample upload. The provider retains voiceprint data, and its deletion API performs soft deletion, not physical erasure. Speech IDs within one meeting are never treated as persistent identities by themselves. See the [meeting implementation and validation limits](docs/6x26-meeting-implementation.md).

### Privacy and local data

**Local history does not mean offline transcription.** Audio is sent to the selected ASR API. When cleanup is enabled, text and active vocabulary are sent to DeepSeek. The app currently talks directly to providers using your personal credentials; it has no UtterLeaf backend or automatic cross-device sync.

Short-dictation audio stays in memory; meeting recordings are retained under the local `meetings/` directory until explicitly deleted. Dictation history and shared API usage are stored at:

```text
~/Library/Application Support/UtterLeaf/ledger.json
```

The directory/file permissions are `700`/`600`. By default, raw and final text remain until manually cleared; settings can retain only final text or usage. Clearing text keeps character counts and usage receipts. It does not erase provider-side records or system backups, and file permissions are not disk encryption.

Credentials, private recordings, history, build products and personal handoffs are excluded from Git. The tracked WAV files under `App/Sounds/` are original UI sounds, not user recordings.

### Usage and billing

- Estimates use the price snapshot attached to each call; CNY amounts display four decimal places. Configurable reference prices are not a promise of your account's actual tariff.
- End-to-end totals include **Doubao + DeepSeek**, with task-level audio duration deduplicated. Missing usage stays unknown rather than being treated as free.
- Optional official checks run every **20 minutes while the app is running**, with startup/wake catch-up and a manual action. They defer during dictation.
- **DeepSeek:** account balance snapshots are reference information, not itemized spend, and never overwrite dictation costs.
- **Doubao:** instance-scoped Volcengine bills require the billing `InstanceNo` and personal read-only credentials, `UTTERLEAF_VOLC_ACCESS_KEY_ID` / `UTTERLEAF_VOLC_SECRET_ACCESS_KEY`, configured locally. Aggregate bills are not automatically allocated to individual calls. Other applications' spending must not be attributed to UtterLeaf.

### Roadmap

| Phase | Scope |
| --- | --- |
| 1 · macOS dictation | Improve the existing personal dictation, insertion and usage experience. |
| 2 · Meetings | Granola-like long-form meeting transcription, speakers, timestamps, edited transcripts, notes and briefs. |
| 3 · Personal iOS | Bring both everyday dictation and meeting transcription/notes to iOS. Mobile audio capture, input integration, personal credentials and platform constraints need separate validation. |
| Later · Slack | Configurable delivery of meeting transcripts and briefs, with explicit destinations and delivery status. |

Phase 3 currently excludes invitation codes, accounts, a shared backend and multi-user quotas. Cross-device sync is undecided.

### Project guide

| Path | Purpose |
| --- | --- |
| `Sources/UtterLeaf/` | Native app, capture, providers, insertion and UI |
| `Sources/UtterLeafCore/` | Protocol, prompt, usage and recording policies |
| `Tests/UtterLeafCoreTests/` | Automated regression tests |
| `prompts/` | Preserved cleanup prompts and JSON-envelope guidance |
| `docs/` | [Product scope](docs/6x23-product-brief.md), [technical handoff](docs/6x23-technical-handoff.md) and implementation notes, primarily Chinese |
| `research/benchmark/` | Research scripts, aggregate metrics and synthetic regression fixtures; no private source recordings |
| `DESIGN.md` / `UX-CONTRACT.md` | Visual and interaction contracts |
| `App/ThirdPartyNotices/` | Third-party attribution |

The native waveform adapts ideas from the MIT-licensed [SpeechWaveAnimation](https://github.com/mvolpato/SpeechWaveAnimation), using SwiftUI Canvas without adding a package dependency. Its notice is bundled with the app. Contributors and coding agents should read [AGENTS.md](AGENTS.md); personal `.codex/` handoffs are local and are not part of a clone.

---

## 中文

UtterLeaf（言叶）是一款对标 Typeless 日常体验的 macOS 私人语音输入工具。按 **Fn** 开始口述，再按 **Fn** 结束：豆包负责转写，DeepSeek 整理表达，随后将文字输入到原来的输入框。

基于 **SwiftUI、AppKit、AVAudioEngine 和 URLSession**，运行 App 无需额外的 Python 服务或 Node 运行时。目前界面为中文。

### 当前状态

**截至 2026-10-26，已有可运行的个人开发版**，仍在打磨稳定性。本仓库尚不提供经过公证的正式安装包或托管 API 服务；会议转录首版已实现，iOS 尚未实现。

最新本地自动测试 **89 项通过**，已做短合成内容 API 检查和真实麦克风、回填试用。Codex 偶发目标捕获失败仍在排查，最新重试修补等待进一步试用；完整五分钟实录尚未验证。测试和构建通过不代表兼容所有输入框。

### 已有功能

- **Fn 开始/结束，Esc 取消**录音或尚未完成的处理；Fn 组合键正常传递，不自动按回车或发送消息。
- **单次最长 5 分钟**，最后 30 秒在胶囊内倒计时，到时自动结束并继续处理。
- **三条可选豆包管线**：流式结束后返回、实时流式、文件转写；新安装不预选管线。
- **可选 DeepSeek Flash 整理**：去除口吃与赘词、保留原意、转换口述符号、规范编号数字。输入使用 JSON 数据封装，不执行录音里的命令。
- **语境词汇表**：帮助规范专有名称及易错拼写，不做无条件全文替换。
- **自动回填及可选预览**：核对原应用、输入框和光标；发生变化时保留稿件供恢复。必要时使用剪贴板粘贴，并在接口允许时读取确认结果。
- **本地历史与用量费用**：原始/最终稿保留策略、CNY 费用估算、供应商成本占比、滚动 7/30 天预算。预算仅作提醒，不限制录音，也不是供应商余额。
- **默认深色**，支持浅色/跟随系统、轻量动态波形胶囊、减少动态效果和三组提示音。

### 构建与配置

需要 **macOS 14+** 和支持 **Swift tools 6.0** 清单的 Xcode/Swift 工具链。

```sh
git clone https://github.com/wyf-ACCEPT/utter-leaf.git
cd utter-leaf
./scripts/test.sh
./scripts/build-app.sh
open .local/UtterLeaf.app
```

构建脚本先暂存、签名并验证，再通过重命名替换 App。其他机器默认使用 ad-hoc 签名，也可用 `UTTERLEAF_SIGNING_IDENTITY` 或被 Git 忽略的 `.local/signing-identity` 指定自己的签名身份。ad-hoc 重编译后可能需要重新授权；正式 Developer ID 签名与公证尚未包含。

1. 在本机配置个人 `DOUBAO_API_KEY` 和 `DEEPSEEK_API_KEY`：优先读取 Keychain 服务 `network.utterleaf.personal`，account 为变量名；否则读取权限为 `600` 的 `~/.llm.env`。GUI 直接读取，无需 shell export。**App 不内置供应商 Key**，不要提交凭证。
2. 在「模型与设置」选择 ASR 管线及是否整理。
3. 为当前 App 开启麦克风与辅助功能权限。
4. 点击目标输入框，单按并松开 **Fn** 开始，再按一次结束；处理期间保持目标和光标不变。输入开始前可按 **Esc** 取消。

文件管线保留实验中验证过的 `audio.data` 接法，但所参考官方文件 ASR schema 未明确列出此字段；兼容性失败时请切换流式管线。

### 会议（Phase 2 首版）

「会议」页面可采集麦克风及可选系统声音，支持暂停/恢复、随手笔记、本机录音回听与删除。会议独立于五分钟听写，初版单场最长三小时。实时字幕会产生额外流式调用，其说话人编号仅为暂定；结束后通过整场 ASR 生成带时间与说话人的转录，再分别生成逐句整理稿和带原文引用的 Brief。

声纹库支持刷新、启停、改名及软删除。注册目前使用你提供的 HTTPS 签名 URL，音频为 5–30 秒清晰单人语音，尚不自动上传本机样本。声纹由豆包保存，删除接口为软删除，不承诺物理擦除；单场说话人编号不会自动当成跨会议身份。参见[实施与验收边界](docs/6x26-meeting-implementation.md)。

### 隐私与本地数据

**本地保存历史不等于离线识别。**音频发送至所选 ASR API；启用整理后，文字和生效词汇表发送至 DeepSeek。当前直接使用个人凭证连接供应商，没有 UtterLeaf 服务端，也不自动跨设备同步。

短听写录音仅存内存；会议录音在本机 `meetings/` 目录保留到手动删除。听写历史及共享 API 用量账本位于 `~/Library/Application Support/UtterLeaf/ledger.json`，目录/文件权限为 `700`/`600`。默认保留原始与最终稿直到手动清除，可改为仅最终稿或仅用量。清除正文仍保留计数与回执，不清除供应商记录或系统备份；文件权限不等于磁盘加密。

凭证、私人录音、历史账本、构建产物和个人交接资料均被 Git 排除。仓库中的 `App/Sounds/` WAV 是原创界面提示音，不是用户录音。

### 用量与官方核对

- 按每次调用的价格快照估算，CNY 显示四位小数；参考价格可修改，不等于账户实际套餐。
- 端到端费用包含 **豆包 + DeepSeek**，同一任务音频时长去重。缺少用量的调用保留未知，不按免费处理。
- App 运行期间每 **20 分钟**检查官方数据，启动/唤醒后补查，听写时延后；也可手动核对。
- **DeepSeek** 返回账户余额参考，不是逐笔账单，不会据此覆盖听写费用。
- **豆包** 查询火山实例账单，需要费用中心的 `InstanceNo`，以及本机配置的个人只读 `UTTERLEAF_VOLC_ACCESS_KEY_ID` / `UTTERLEAF_VOLC_SECRET_ACCESS_KEY`。汇总账单不会自动摊为逐次费用，也不能把其他应用消费归给言叶。

### 后续路线

| 阶段 | 范围 |
| --- | --- |
| Phase 1 · macOS 听写 | 继续打磨现有私人听写、回填与用量体验。 |
| Phase 2 · 会议 | 类似 Granola 的长时会议转录、说话人、时间戳、整理稿、笔记与 brief。 |
| Phase 3 · 自用 iOS | 同时包含日常听写和会议转录/笔记；单独验证移动端采音、输入入口、个人凭证与系统限制。 |
| 后续 · Slack | 按配置分发会议转录与 brief，明确目标和发送状态。 |

Phase 3 暂不考虑邀请码、账户、统一服务端和多人额度；跨设备同步方式待定。

### 开发资料

源码在 `Sources/`，测试在 `Tests/UtterLeafCoreTests/`，原始整理 prompt 与封装说明在 `prompts/`。[产品需求](docs/6x23-product-brief.md)、[技术交接](docs/6x23-technical-handoff.md) 与实施记录在 `docs/`；[DESIGN.md](DESIGN.md) 和 [UX-CONTRACT.md](UX-CONTRACT.md) 维护视觉与交互约定。`research/benchmark/` 保留研究代码、汇总指标与合成回归，不包含私人原始录音。

波形参考 MIT [SpeechWaveAnimation](https://github.com/mvolpato/SpeechWaveAnimation)，使用原生 SwiftUI Canvas 适配，无新增 Swift 包依赖，许可随 App 打包。开发前请阅读 [AGENTS.md](AGENTS.md)；`.codex/` 个人交接资料仅保存在本机，不随 clone 提供。
