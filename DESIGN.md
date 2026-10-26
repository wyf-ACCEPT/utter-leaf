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

Usage composition uses the same two 7/30-day budget bars: remaining LeafTheme.leaf as the dominant green fill from the left (orange below20%), then muted dictation #A6B5AC / #3F5E4B (light/dark) and meetings #729B80 / #6D947A on the right. Each segment has a text percentage and accessibility value; color is never the only identifier. The main Usage page shows purpose-split spend and separate dictation-per-1k / meeting-per-hour unit costs. Provider/model/date filters and call accounting remain in the bounded UsageDetailsView sheet; official reconciliation is a disclosure instead of a permanent large card.

Meeting floating captions initially center in the active screen, with a native draggable header and persistent location within the running app. Settings offer 2/3/5 text lines (default3), 0–65% background transparency (default25%); text remains fully opaque. Native nonactivating controls collapse to a260×52pt restore bubble or hide the overlay; the meeting page can show it again. Expanded height is100+28×line-count pt, width at most660pt, clamped to the current display. The panel accepts mouse interactions without becoming key/main. Source and provisional speaker identity remain explicit, with short lifecycle/utterance transitions. It reuses LeafTheme colors, system typography and reduced-motion handling; no extra waveform, model or network call is added.

SidebarItem owns a fixed20×20pt aspect-fit SF Symbol slot and10pt text gap. Meetings uses person.2, keeping all navigation labels aligned without the wide person.3.sequence symbol.

Live meeting transcripts share the bounded transcript scrolling contract: a360pt scroll area with visible native scroll indicators, a lazy stack and selectable speaker/timestamp text. Growing partial text never increases the outer page height. Final transcripts retain their420pt viewport.
