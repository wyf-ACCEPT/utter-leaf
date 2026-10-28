---
version: alpha
name: UtterLeaf
description: Native personal dictation with mist-white surfaces and botanical green.
colors:
  primary: "#2D5E46"
  background: "#F5F8F6"
  surface: "#FFFFFF"
  ink: "#1B2A23"
  muted: "#5B6A62"
  border: "#D3DDD6"
typography:
  display:
    fontFamily: "SF Pro Rounded, PingFang SC, system-ui"
    fontSize: "37.76px"
  body:
    fontFamily: "SF Pro, PingFang SC, system-ui"
    fontSize: "16px"
  utility:
    fontFamily: "SF Mono, monospace"
    fontSize: "12px"
rounded:
  DEFAULT: "12px"
  surface: "18px"
  action: "999px"
spacing:
  page: "34px"
  surface: "22px"
  section: "18px"
components:
  Surface:
    rounded: "18px"
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
  SecondaryText:
    textColor: "{colors.muted}"
  LeafSegments:
    height: "52px"
    rounded: "14px"
  Divider:
    backgroundColor: "{colors.border}"
  PrimaryStyle:
    backgroundColor: "{colors.primary}"
    height: "46px"
  RecordingPill:
    width: "330px"
---

# UtterLeaf Design System

## Overview

### Creative North Star

A small living leaf beside a page of words. A quiet personal macOS instrument for Jason's daily Chinese/English dictation. The user explicitly chose mist white, botanical green, and a compact waveform capsule on 2026-10-23. Expression is concentrated in the leaf mark and recording capsule; settings and costs stay practical.

User later requested dark mode as the first-launch default. The selected original vector leaf/bubble/wave mark replaces the temporary SF Symbol.

Personal Chinese UI with English model names, system fonts and PingFang fallback. This is not a Japan-market product. Avoid black audio workstations, marketing gradients, fake metrics, decorative serif headlines and oversized dashboards.

Token ownership: `Sources/UtterLeaf/Views.swift:LeafTheme` is the canonical runtime palette. This file mirrors its RGB values to the nearest hex byte. Shared `Surface`, `PrimaryStyle`, `PageHeading` and `Waveform` own geometry and type; native AppKit/SwiftUI controls own platform focus, popups, scrollbars and sheets. No CSS or web adapter is used.

## Colors

Leaf green is the primary action and selected navigation. Ink is body text, muted green-gray is supporting text, pale mist owns the shell and fine borders separate surfaces. Use native red/orange for danger/warning with a text description. Both light and dark are owned themes; dark is the first-launch default. Settings offer dark/light/system and persist the choice. Native popups and titlebar follow the chosen appearance. Dark tokens: background #141C18, surface #1E2922, leaf #9FD6B5, ink #E7F0EA, muted #A8BBB0, border #35463C, primary-action ink #102A1C. Light action ink is white. Contrast and readable focus require native device checks.

## Typography

User requested larger overall type: shared LeafType scales previous explicit sizes by 1.18 with a 12pt floor. Page headings are 37.76pt medium, body is 16–18.88pt, captions 14pt, data values 23.6pt and technical IDs at least 12pt. Segment labels use 14pt to preserve multi-option geometry. Chinese uses platform fallback. Mixed-language text stays selectable. Long transcript lines wrap; IDs remain fully available in details.

## Layout

A 220pt sidebar and a scrolling content panel, maximum inner content width 1040pt, 34pt page padding, 22pt surface padding, 18pt vertical rhythm. Minimum window 900×680pt, default 1160×840pt; an existing saved frame is respected. Native desktop only; no mobile/browser target. Lists explicitly load 30 more rows at a time. Each main screen scrolls naturally. The call history is a separate 700×550pt sheet with a fixed header/footer and its own bounded scroll area, never a nested scroller on the main usage page. Recording sits in a fixed 420×120pt nonactivating, non-key panel above the screen bottom; only its capsule contents morph, preserving input focus.

## Elevation & Depth

Quiet translucent-white surfaces with fine green-gray rules. Static surfaces have no shadows. Only the floating recording panel receives the native window shadow. Busy and feedback content reserve stable action geometry.

## Shapes

18pt surfaces, 12pt navigation selection, capsule primary action and recording overlay. An original leaf/bubble/wave vector supplies brand identity; SF Symbols supply functional iconography. No custom font or remote visual asset dependency.

## Components

`Surface` and `PageHeading` are shared across all five screens. All enumerable choices use the shared LeafSegments control: theme, ASR, retention, dates, provider, model, character denominator and prompt versions. The selected surface uses matchedGeometryEffect with a 0.32s spring and 0.86 damping; hover and selected/disabled semantics remain visible. Arrow moves and native button keyboard activation are supported. DatePicker itself remains system owned. Native confirmation dialogs own focus and Escape behavior. Text fields and editors retain standard keyboard and IME behavior. Disabled controls do not invoke actions. Primary pressed state changes opacity/scale; all action labels describe the result.

Selection indicators slide on click and settle with a restrained spring; Reduce Motion disables them. The only continuous animation is the live audio meter: bounded recent RMS history, 35ms attack / 160ms release and three continuous sine/envelope paths in native Canvas at a target 30fps. The waveform exists only during recording; processing uses status and a small spinner. Reduce Motion removes phase motion and lowers updates to 5Hz. Sidebar hover uses 120ms ease-out, a soft preview surface and pointing-hand cursor. Primary press feedback is immediate; no page-entry animation or decorative ambient motion. Inline statuses persist until the next action; critical errors do not disappear as toasts. Busy actions cannot be double-submitted.

Costs use original currency labels, monospaced digits and explicit estimate/actual wording. No invented usage chart is shown when data is empty. VoiceOver labels are required on icon-only controls. Navigation and waveform should remain quiet beside long text.

## Do's and Don'ts

- Do insert automatically into the verified original input; keep recovery text editable and make its destination visible.
- Do preserve measurements, errors, raw text and final text as distinct states.
- Don't imply that estimates are invoices or tokens are characters.
- Don't trade focus safety or native keyboard behavior for decorative motion.

Usage starts with rolling 7-day / 30-day local budgets (CNY 5 / 20 by default), showing remaining percentage, money and sample-derived character allowance. These are editable reminders, never provider balances or enforcement. Existing filters stay below; unit costs live together at the bottom. Budget forms use native labelled fields, inline validation, Save/Cancel and Escape dismissal.

Budget rows show Doubao and DeepSeek shares of known estimates and their ratio; unknown amounts never become zero-cost data. The main usage page has a compact View Details entry. CallHistorySheet keeps the chosen filter description and loads 30 rows at a time. Native nested receipt sheets preserve the history position and allow Escape/Close without changing billing.

Official reconciliation is a shared BillingSyncView on Usage and Settings: stable manual-sync button, inline last-success/error status and preserved cached data. BillingSettings owns automatic-sync toggle, scoped instance/product fields, explicit exclusive-instance assertion and local credential instructions. Credentials never appear in fields or logs. Native sheet scroll is bounded with Save/Cancel and dirty-discard confirmation. Provider balance and instance bill totals stay visually separate from per-call actual costs.

PillPresentation owns the capsule lifecycle: entry unfolds/fades from a small bottom anchor (~380ms spring); waveform-to-processing crossfades while width moves 350→290pt; a truthful completion/retained/cancel status briefly settles at 230pt, then contracts/fades (~200ms). SwiftUI animation runs independently of API/insertion work. Revision/cancellation guards prevent an old exit from hiding a new session. Reduced Motion uses only a short opacity fade. The Canvas phase is continuous and never resets at arbitrary uptime intervals.

UtterLeafWindow owns double-clicks in the top titlebar band: Fill the current desktop visible frame (between menu bar and Dock), then restore the saved complete frame, including position. It never enters a new Space from a normal window. Traffic lights and attached sheets are excluded. A restrained 220ms frame animation ignores repeated gestures; Reduce Motion applies immediately. Manual resize/move establishes the next restore frame; local saved frames support relaunch while filled. Other window interactions remain AppKit owned.

LeafInputChrome is the shared single-/multiline input owner. SwiftUI TextField/TextEditor keep native text editing and IME behavior, with plain text-field styling, hidden editor scroll background, a 44pt minimum target, 12pt horizontal / 10pt vertical inset, 12pt rounded surface, a subtle border and leaf-green focused outline. Hover slightly strengthens the border; keyboard focus stays explicit; disabled controls dim. Native blue/bezeled field chrome is replaced within these controls, not globally through appearance proxies. Vocabulary sheets use the app mist background. Shared style covers vocabulary/search, budget/billing fields, pricing, prompts and editable transcripts.

Quota card refinement: show the 7-day and 30-day bars consecutively, with each row limited to remaining percentage, used/budget/remaining money and estimated remaining characters. Render one cost-composition footer labelled “近 30 天”; show its missing-usage warning only for at least five calls. Keep all missing-call accounting and receipt details intact. Waveform shape and capsule geometry are unchanged; visual gain is 1.7× with a -50dB near-silence floor, bounded inside the existing canvas.

Sound feedback: SoundSettingsView shares LeafSegments for A · 轻触 (default), B · 木滴, C · 清铃, a native volume slider, enable/mute and an explicit three-cue preview. Preferences are optional for old ledgers and persist locally. SoundFeedback uses bundled original PCM WAVs through AVAudioPlayer, no network/dependency. Start cue finishes plus a 30ms tail before microphone capture; stop plays after microphone stop; completion plays only after confirmed insertion, never unverified paste/preview/failure. Settings audition is disabled during dictation; cancelling startup stops playback and task cancellation prevents microphone start. Playback failure never blocks dictation.

Each 7/30-day quota row now displays “已写 X 字” alongside the estimated remaining characters. Count finalCharacters from distinct jobs created inside that rolling window, independent of the number/provider/currency/completeness of API receipts. Raw-only unfinished transcription is excluded. Retention clears text but preserves counts. The tooltip discloses punctuation/whitespace and preview/copy inclusion.

Meetings use the existing LeafTheme, Surface, LeafInput and LeafSegments owners. The primary canvas is a quiet notepad, with peer tabs for original transcript, cleaned transcript and Brief. Speaker names and source timestamps are structural navigation, not decorative chat bubbles. A bounded transcript scroll area avoids stretching the entire page. Voiceprint management is a bounded sheet with secure URL input, explicit cloud registration and soft-delete language. Existing capsule geometry is unchanged; meeting capture is a separate session with visible controls.

Usage composition uses the same two 7/30-day budget bars: remaining LeafTheme.leaf as the dominant green fill from the left (orange below20%), then muted dictation #A1ADA6 / #3F594A (light/dark) and meetings #939F98 / #4B6555 on the right. Each segment has a text percentage and accessibility value; color is never the only identifier. The main Usage page shows purpose-split spend and separate dictation-per-1k / meeting-per-hour unit costs. Provider/model/date filters and call accounting remain in the bounded UsageDetailsView sheet; official reconciliation is a disclosure instead of a permanent large card.

Meeting floating captions initially center in the active screen, with a native full-window interaction surface and persistent location within the running app. Settings offer 2/3/5 text lines (default3), 0–65% background transparency (default25%); text remains fully opaque. Native nonactivating controls collapse to a260×52pt restore bubble or hide the overlay; the meeting page can show it again. Expanded height is100+28×line-count pt, width at most660pt, clamped to the current display. The panel accepts mouse interactions without becoming key/main. Source and provisional speaker identity remain explicit, with short lifecycle/utterance transitions. It reuses LeafTheme colors, system typography and reduced-motion handling; no extra waveform, model or network call is added.

SidebarItem owns a fixed20×20pt aspect-fit SF Symbol slot and10pt text gap. Meetings uses person.2, keeping all navigation labels aligned without the wide person.3.sequence symbol.

Live meeting transcripts share the bounded transcript scrolling contract: a360pt scroll area with visible native scroll indicators, a lazy stack and selectable speaker/timestamp text. Growing partial text never increases the outer page height. Final transcripts retain their420pt viewport.

Brief source references are a local presentation preference, default off. Off shows a bounded selectable reading view and copies citation-free text; on exposes the retained editable source draft and source lookup. The “编辑原稿” action explicitly opens that source view. The model still generates and validates citations, so switching never calls an API or destroys the source draft. Existing meetings follow the same setting.

The meeting overlay doubles as a recording indicator when live captions are off: a360×136pt translucent timer card using the same header, controls and typography. A record symbol with “正在录制” or pause symbol with “已暂停” identifies state without color alone. Collapsed mode retains the timer. Time follows recorder elapsed seconds, without decorative animation or network requests.

Meeting aftercare uses one next-step card above the content tabs, with actual completion states for original transcription → cleaned transcript → Brief. The current next action is the leaf primary button; text explains the result before API invocation. Incomplete cleanup never marks the second step complete. Existing notes/read views are preserved during background completion, avoiding focus-stealing navigation; explicit workflow actions switch to their destination tab. Advanced reprocessing remains in a disclosure. Next-meeting capture settings collapse while reviewing an existing meeting. Content actions sit above the bounded viewer: shared Copy and Export TXT always use the selected version, and Brief respects source visibility. Native fileExporter owns save/cancel/overwrite; no custom save dialog or cloud export.

MeetingOverlayInteractionView is the canonical pointer owner for the floating meeting window. It sits above the SwiftUI text in a native container: all non-control areas drag through AppKit performDrag, including text, padding and empty regions. Three independent24×24pt native NSButton regions own Pause/Resume, Collapse/Expand and Hide; they accept first clicks, refuse keyboard focus, and expose labels/tooltips. The existing360×136/260×52 geometry is retained; collapsed time appears before the state label. Open-hand cursor marks drag regions; buttons use the pointing hand. Pause/Resume invokes the existing MeetingModel.togglePause capture lifecycle, not just a cosmetic status switch.

Meeting processing uses a shared MeetingProcessingView: real upload fraction and validated turn/chunk completion are determinate; save/preparation/provider queue/recognition use native indeterminate bars with elapsed wait time. No synthetic recognition percentage. An incomplete cleaned tab is an empty state, not a raw-text fallback. Speaker labels are “说话人 N” above shared LeafInput fields in an adaptive260pt grid (2–3 columns at normal widths, one when narrow). Meeting history is a320pt lazy scrolling viewport, with search above it. Native raw-turn editor preserves immutable ASR text and explicitly invalidates derived cleanup/Brief.

The optional three-name suggestion strip sits beside the title workflow without replacing its primary CTA. Selecting a local-date-prefixed kebab-case candidate applies a shared TXT/M4A stem; actual local audio conversion preserves source WAV. Already-consumed dictation/meeting colors are intentionally close and muted, while remaining allowance stays the dominant bright leaf green.

External recording import is a peer secondary action beside New Meeting, using native NSOpenPanel filtered to audio. Copy/conversion progress is separate from provider processing; Cancel Import cancels local work. Review reuses the same source/cleaned/Brief workflow and existing responsive fields. No microphone prompt, waveform or live caption stream appears during file import.

## Personal iPhone dictation · 2026-10-26

The first iOS version deliberately includes dictation only. Flutter owns the main app, using `mobile/lib/main.dart:Leaf` as its theme adapter for the same six dark botanical tokens. A lightweight SwiftUI keyboard uses matching static colors; no Flutter runtime runs in the extension. Main recording, busy, recovery and ready states preserve one primary-action location. Real RMS drives the waveform only during recording; processing shows an indeterminate activity indicator. Reduce Motion removes phase motion. A 320pt display scrolls vertically and the app title truncates safely. Credential sheets own masked values and explicit Save; setup explains Full Access and the user-owned return gesture. No usage dashboard or meeting screen is ported.

The original macOS theme remains canonical for shared brand colors; iOS adopts platform-sized type and 44pt-or-larger actions. Native Swift owns recording, interruption, bounded networking and cross-process delivery. Keyboard insertion is request-scoped, expires after 15 minutes, claims before writing, and automatically inserts only in the unchanged original document/caret context. Otherwise Insert is an explicit action. No Return/Send is generated. A personal-only guarded native Back adapter attempts return after audio capture is running; unsupported OS versions keep a visible manual-return path. Optional fresh host lookup is used only for the WeChat resume scheme, never a cached source or arbitrary bundle launch. Reassess this non-public compatibility path before distribution. Native `Link` launch and background processing require physical-device acceptance.


Keyboard backdrop correction (2026-10-27): native keyboard-style UIInputView owns the extension backdrop and bottom dock as a single system surface. UIKit and SwiftUI hosting layers remain transparent; text follows keyboard appearance, with botanical accents adapted for light/dark. Main app colors remain unchanged. Simulator light Safari and a dark native synthetic input fixture were visually inspected with no surface color seam.


Return navigation feedback correction (2026-10-27): the same native requestReturn owner serves automatic and explicit return. The button displays a pending spinner/label, suppresses duplicates, and uses a persistent live status distinguishing missing source from a rejected request. Inactive activation is not a completed return. Normal builds keep recording enabled; test-only navigation flags remain explicit.


Keyboard delivery refinement (2026-10-27): the primary Start/Stop capsule is centered200×80pt inside the existing260pt keyboard surface;12pt vertical spacing preserves the header/status/footer. The space action is removed; delete and optional next-keyboard controls retain44pt targets. System backdrop remains continuous. Stop explicitly binds the current input proxy and surrounding context for this request, allowing automatic delivery after the app handoff has recreated the original proxy. The Insert action is removed; a changed target retains the result and shows waiting/recovery status.


Keyboard touch refinement (2026-10-27): delete uses a 64x52pt hit region with a 28pt symbol and subtle rounded backing. Routine idle/inserted status is visually and accessibly hidden while its reserved slot keeps the capsule stable. Recording, processing, waiting-result and actionable error/permission feedback remain visible in secondary caption styling.


Explicit keyboard action key follows the host returnKeyType (Search, Send, Go, Next, Done or newline). Only a user tap inserts the return character; dictation completion still never submits. Host text/selection changes refresh the label, and the host owns actual submission or newline semantics.


Recording waves use measured RMS-derived level on both Flutter home and the native keyboard. The shared state contains a bounded scalar only, updated with the existing recorder tick. Near silence is nearly flat, with 220ms amplitude smoothing; Reduce Motion stops travelling phase without hiding measured level. Processing replaces the wave. Capsule dimensions stay unchanged.


The iOS app has persistent Home, Usage and Settings destinations. A native platform view uses UIGlassEffect on iOS 26 and system blur on earlier iOS, with opaque fallback for Reduce Transparency. Active recording belongs to the coordinator and survives tab changes; a fresh keyboard recording returns the main app to Home. Settings owns key editing, disabled during capture/processing. Usage combines real Mac/iPhone metadata in the verified personal paid-team private container. Empty never-synced caches show a waiting state rather than fabricated zero/full-allowance figures. Sync status and last successful transfer stay distinct from account readiness; recordings, transcripts and credentials are excluded.


The keyboard return action is centered independently of the optional globe and trailing delete key, sharing the primary recording capsule center axis at every width.


The completed paid-team migration preserves the verified bundle, App Group, deep-link scheme and keyboard Full Access. Both app and keyboard are named “言叶”. Private usage synchronization uses iCloud.network.utterleaf.usage; the previous container and account-bound cache remain intact. Never infer successful synchronization from account availability.


After user-confirmed paid-team WeChat return and insertion, the app and keyboard display names return to “言叶”. Bundle, scheme, App Group, signing and Keychain identity remain those of the verified paid-team installation.


Navigation motion refinement: one shared native glass selector slides continuously behind the three buttons. Taps spring to the destination; horizontal dragging previews the nearest destination and commits once on release. Cancellation restores the original tab without a Flutter callback. Programmatic selection updates do not echo callbacks. Reduce Motion disables spring/stretch while preserving direct manipulation. Existing recording ownership and native button accessibility remain unchanged. Evaluated [native_glass_navbar](https://github.com/TechSupportz/native_glass_navbar) and [Liquid-Glass-Bar](https://github.com/teiseong/Liquid-Glass-Bar); full UITabBarController embedding was tested but discarded after touch integration failed. The shipped implementation retains the working UIGlassEffect bridge without an added package or copied source.


Private usage dashboard (2026-10-28): retain two budget bars, with bright remaining allowance and subdued used segments. Device/purpose spend shares the existing summary; full recent-call details live in a bounded bottom sheet with source filtering. Shared budget edits persist locally, propagate with deterministic conflict handling, and never block dictation. An empty initial cache shows explicit waiting; failed sync preserves prior totals and last-success time. Phone API collection begins with this version.
