# UtterLeaf UX contract

Visual ownership: [DESIGN.md](DESIGN.md). Platform: native macOS 14+, verified build host macOS 26.6.2 arm64. UI locale zh-Hans; dates use the Mac's locale/timezone. New ASR and DeepSeek estimates both use official/reference CNY rates and display four decimals. Old currency snapshots remain immutable and, if present, are shown separately. No Japan-market scope.

## Business-context sources

| Policy | Authority | UI consequence |
|---|---|---|
| Model choice and preview | User decisions 2026-10-23; docs/6x23-product-brief.md | No initial ASR default; default automatic insertion after cleanup |
| Personal credentials | AGENTS.md; docs/6x23-technical-handoff.md | Local allowlist only; no OpenRouter |
| Retention | User decision 2026-10-23 | Keep raw/final text until explicit clear; audio in memory only |
| Usage and money | docs/6x23-product-brief.md | Independent calls, frozen rate snapshots, unknown failures, original currencies |
| Insertion | docs/6x23-product-brief.md | Automatic insertion with verified target/selection; editable fallback; no Send key |
| v6 data boundary | prompts/README.md | Fixed JSON transcript envelope; no tools |

## Canonical UI Map

| Capability | Canonical owner | Source of truth | Allowed variants | Verification |
|---|---|---|---|---|
| Select/Listbox | LeafSegments | Views.swift / SettingsView.swift | Shared animated segments; native DatePicker only for calendar entry | Native UI switching + keyboard inspection |
| Date | SwiftUI DatePicker | UsageView | Native date popup | Native UI inspection |
| Form | SettingsView / CallDetail / VocabularyEditor | Native TextField and TextEditor | Multiline prompt, transcript editor | Build + native UI |
| Scrollbar | SwiftUI ScrollView / TextEditor | macOS system behavior | Native system appearance and visibility preference | Native UI inspection |
| Toast | AppModel.message | DictationView persistent inline status | Settings feedback | Failure recovery checks |
| CRUD | LocalStore | AppModel and SettingsView | Text clear confirmation; vocabulary CRUD sheet; amount reconciliation sheet | Unit tests + UI |

## Flow ledger

- Idle → starting → recording → transcribing → cleaning → inserting → idle, with editable preview on failure or in optional preview mode. Cancellation and failures return to an actionable state; a new recording first preserves pending text according to the configured history retention. Copying saves and closes the retained preview, leaving recording ready.
- A standalone Fn press/release toggles recording. The session event tap consumes Fn modifier events to avoid the system Globe action. Fn chords do not toggle, other key events pass through, and interrupted gestures reset after tap disable/sleep/session deactivation. Monitoring starts only when Accessibility is trusted and retries automatically after permission changes. Existing Typeless/Codex shortcuts and configuration are untouched. Capture target before showing the overlay. Stop/cancel are also buttons.
- Stream ASR opens after microphone consent, sends real-time 200ms frames, and waits for a final response. File ASR submits only after recording ends. Maximum 2 minutes. No automatic network retries.
- A cleanup retry creates another billable call under the same business ID. Raw text survives cleanup failure; use raw/copy/retry are available.
- Automatic insertion checks that the original app is still frontmost and verifies the focused element + selected range before writing; it never activates another application. Manual “输入到原应用” may reactivate the captured application, then performs the same checks. Codex/ChatGPT and browser composers use Cmd+V through the normal keyboard route; other apps may use AXSelectedText only after text/caret readback. When unsupported or confirmed unchanged, revalidate and issue only Cmd+V to the verified foreground target, temporarily leasing the pasteboard and restoring it only if its ownership/text still match. Never send Return. An uncertain AX write is not retried with paste. A dispatched paste is marked separately when the destination cannot acknowledge its text, avoiding an automatic duplicate retry. Failure retains editable text and opens the app; successful automatic insertion does not open the app.
- Capture uses RMS validation. No input, device configuration change, permission denial, provider error and network timeout are actionable errors. Do not claim proven recovery until runtime exercised.
- History search is local, no remote debounce. Clear button resets query and pagination. Load more adds 30 records. Sensitive query state is memory-only, never URL persisted.
- Unsaved prompt editor changes and transcript drafts survive screen navigation in AppModel. Dirty state and explicit save/revert controls are shown; the app does not silently persist unsaved prompt changes.
- Saving price/pipeline/retention affects future calls. Existing price snapshots remain immutable. The CNY end-to-end summary joins ASR and cleanup costs over unique business audio durations; provider breakdowns remain separate. Unknown amounts remain unknown. Actual amounts require manual request-specific billing reference.
- Clearing stored text is an explicit destructive native confirmation, retaining anonymous job/call counters and the current preview. It does not claim forensic erasure or clearing vendor data.
- Local storage is Application Support/UtterLeaf with directory mode 700 and ledger mode 600. Credentials and audio never enter the ledger. Corrupt storage fails closed without overwriting the original file.
- LeafSegments owns selection/hover/spring/reduced-motion behavior; native buttons, fields and date pickers own keyboard, VoiceOver and IME behavior; icon-only actions carry labels. Reduce Motion disables waveform animation. Testing actual assistive technology remains device acceptance work.

## Verification scope

Use native app inspection instead of browser workflows. Web HTML/CSS lint rules are not applicable to SwiftUI. Core tests cover protocol, estimates, Unicode denominators, immutable snapshots and JSON framing; native UI and cloud smoke receipts are separate evidence.

## Latest device evidence

The personal Apple Development build has a stable certificate-based designated requirement and audio-input entitlement. After removing/re-adding the old ad-hoc Accessibility entry, the running app reported Accessibility authorized. A real 14.1833-second recording completed ASR + cleanup with 61 raw and 45 final scalar characters. No target captured from the app-window start correctly prevented insertion. Full external-target insertion is a separate acceptance step. Larger fonts and shared sliding segments were observed in native screenshots, including changing ASR selection.

## Fn shortcut update · 2026-10-23

User explicitly requested direct Fn binding and reported closing Typeless. The old Carbon Control+Option+Space shortcut was replaced by a CGSession event tap for Fn in the app and external inputs. No Typeless or system keyboard configuration was modified. Only Fn gesture state and chord use are inspected; keyboard text is never read, stored or logged. Seven new gesture tests pass (24 total). Physical external-target insertion acceptance was explicitly deferred by the user and remains deferred.

## Automatic input, vocabulary and responsive meter · 2026-10-23

User replaced the initial preview-first decision with automatic input after Fn ends. “确认回填” was the former manual insertion action and is now labeled “输入到原应用” in recovery/preview mode. Copy/new recording no longer leaves the user locked behind a preview.

Vocabulary is a first-level sidebar route, aligned with History and Usage. A list of 30 entries at a time supports local search/clear, enabled switches, editor validation and a native destructive confirmation. Unsaved editor changes require an explicit discard action. Typeless/Typeface is the user-requested seed; contextual glossary JSON is sent as reference data, not instructions. Recording snapshots enabled terms; retry cleanup uses current terms. Terms are not a global raw-ASR replacement.

LiveWaveform uses three native Canvas sine/envelope paths inspired by MIT SpeechWaveAnimation, with no Swift package dependency. Bounded recent RMS amplitudes drive local height. Only recording mounts the waveform; processing shows status and a spinner. Reduced motion removes phase movement and uses 5Hz updates.

HandCursor and SidebarItem own pointer feedback. Navigation hover uses a lighter surface than selected; selection persists after clicking. Segments and primary actions share the pointing-hand behavior; disabled actions reset the cursor and omit clickable feedback.

- UsageBudgetView owns rolling 7/30-day budget guidance, independent of detail filters. Optional persisted preferences migrate old ledgers safely. Defaults CNY 5/20 are user-editable, never charged/enforced. Remaining percent is clamped; unknown costs are disclosed and excluded; projections require complete successful CNY task samples and deduplicate final characters. Unit costs are consolidated at the bottom of the main page.
- Escape cancels active starting/recording/transcribing/cleaning through the same abort/token invalidation as Cancel, consuming its matching key-up only for that session. It passes through while idle or during already-started insertion.

- Each quota row shows Doubao / DeepSeek shares and their known-estimate ratio within the same rolling CNY window; no division by zero, no mixed actual/estimate basis. Main usage replaces inline call rows with View Details. CallHistorySheet owns independent bounded scrolling, 30-row incremental loading, empty state and a fixed close control. Filters are inherited from the main page; receipt/bill reconciliation opens a nested sheet and closing returns to the same call list position.

## Official billing sync

User authorized local estimation plus read-only official checks every 20 minutes. BillingSync owns this schedule inside the running app (no Codex automation, launch daemon or sleep wake). Start/wake checks persisted per-provider attempt times; automatic checks defer while dictating. Manual checks can run with automatic checks disabled. One in-flight task; failure preserves last success, no rapid automatic retries. Local storage failure disables sync.

BillingService uses a separate ephemeral session, pinned official hosts, no redirects, cookies/cache/body logging. DeepSeek balances are account snapshots, never per-call charges. Volc V4 signed ListBillDetail is scoped by required InstanceNo and optional Product, uses complete bounded pagination, rejects warning/scope/currency/date/count/schema mismatches and deduplicates bill detail IDs. Three-month boundary windows are supported when 30 days spans three months. New snapshots apply only to unchanged scope. Keys are allowlisted/local only.

Official instance payable totals are separate from manual per-request billedAmount. Interval comparisons require an explicit exclusive-instance assertion and count each recorded request once across overlapping charge intervals. Never allocate aggregate or balance deltas to requests. Missing/delayed bills remain incomplete evidence. Failed/cancelled terminal requests estimate only known sent/submitted audio or returned tokens using frozen price snapshots; pending/unsent usage remains unknown. Optional fields migrate old ledgers safely.

## Window and capsule motion

User clarified that top titlebar double-click means desktop Fill / restore, not native full-screen Spaces. UtterLeafWindow saves both the original frame and applied visibleFrame, fills only the current screen available area, then restores original position and size. Repeated gestures during the frame animation and modal/traffic-light interactions are excluded. Manual move/resize becomes a new restore point; stored geometry survives relaunch and off-screen restoration is clamped after display changes. An already native-fullscreen window exits that mode before desktop fill; normal double-click never creates a Space. No system preference is changed.

PillPresentation is the shared capsule animation owner. RecordingPanel is nonactivating and cannot become key/main. Its fixed transparent 420×120pt canvas is ordered once per session; entry, stage width/content transition, brief truthful terminal status and shrink/fade are SwiftUI owned. Busy work proceeds without waiting for motion. Terminal states stop intercepting pointer input. Finishing tasks are cancellable/revision guarded so a new Fn session cannot be hidden by a prior exit. Quit removes the panel immediately. Reduce Motion has opacity-only entry/exit and no animated width/scale/offset changes. Waveform exists only during recording; processing crossfades to a spinner and status text.

短录音无文字提示：实际录音时长 ≤3 秒且仅为 asr_empty / silent_audio 时，保留调用状态和用量，清空提示并回待机，不打开主窗口。超过 3 秒的空录音及权限/网络等其他错误仍显示。识别成功的短句继续正常整理和回填。60 项测试覆盖 3 秒边界和真实错误不被隐藏。

## Shared text-input appearance

LeafInputChrome (LeafInput.swift) owns native TextField/TextEditor appearance across forms and searches. It uses explicit FocusState binding (or accepts the vocabulary editor's existing binding), visible leaf focus and hover/disabled states, rounded adaptive surface and native editing/accessibility semantics. No custom key handling or IME changes. Native scroll content backgrounds are hidden for multiline editors; editor heights and page/sheet scroll ownership stay local. Validation, first-field focus, dirty-state confirmation and Save/Cancel behavior remain unchanged.

Quota summary footer uses the 30-day window once (7-day is a subset, never sum warning counts). Each bar keeps its own money and character projection. Missing-usage warning is visible at >=5 calls in the quota footer; smaller counts remain available in call details and estimate completeness accounting. AudioEnvelope now gates below -50dB and SpeechWaveCurve applies 1.7× visual gain, clamped to existing amplitude bounds; this does not change microphone PCM, ASR payload or capsule size.

Sound feedback: SoundSettingsView shares LeafSegments for A · 轻触 (default), B · 木滴, C · 清铃, a native volume slider, enable/mute and an explicit three-cue preview. Preferences are optional for old ledgers and persist locally. SoundFeedback uses bundled original PCM WAVs through AVAudioPlayer, no network/dependency. Start cue finishes plus a 30ms tail before microphone capture; stop plays after microphone stop; completion plays only after confirmed insertion, never unverified paste/preview/failure. Settings audition is disabled during dictation; cancelling startup stops playback and task cancellation prevents microphone start. Playback failure never blocks dictation.
