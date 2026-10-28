# UtterLeaf for iPhone

Personal Flutter iOS dictation app. Meetings, accounts, shared backend and public distribution are outside this first version.

## Components

- Flutter owns the Chinese recording, recovery, setup and credential screens.
- Native Swift owns AVAudioEngine capture, 16 kHz mono PCM conversion, the existing Doubao WebSocket framing and DeepSeek Flash cleanup. The main app keeps recording while the user returns to their text field.
- A small SwiftUI keyboard extension opens `utterleaf://dictate`, sends stop/cancel commands over an App Group, and inserts finished text through `UITextDocumentProxy`. No Flutter engine, microphone or API credentials run in the keyboard process.
- Personal credentials live in device-only Keychain entries. An optional ignored `ios/PersonalKeys.plist` seeds a personal development installation. Never distribute a seeded build. The keyboard receives only the last dictation result and state, not credentials. Original target context remains inside the extension's local preferences and is never sent to providers. A single-use, 30-second App Group ticket is required before a keyboard URL can start recording; a random external URL cannot start the microphone.

## Build and install

Requirements: Flutter, Xcode with iOS SDK, an Apple ID signed into **Xcode → Settings → Apple Accounts**, and an unlocked paired iPhone with Developer Mode enabled. App and keyboard must use the same development team and App Group entitlement. Personal-team capability support depends on Apple's provisioning; do not assume that a certificate alone is sufficient.

```sh
cd mobile
flutter pub get
python3 scripts/prepare_host_plugin.py
flutter analyze
flutter test
flutter build ios --simulator --debug
# Optional personal key seed, read only from the two allowlisted local keys:
python3 scripts/provision_personal.py
flutter build ios --release
```

Open `ios/Runner.xcodeproj` for signing. Targets: Runner and UtterLeafKeyboard. Bundle IDs: `network.utterleaf.personal.mobile` and `.keyboard`; group: `group.network.utterleaf.personal.mobile`. Change all three together if Apple requires another identifier. A different team can be passed to xcodebuild with `DEVELOPMENT_TEAM=...`. Do not commit profiles, keys, local signing overrides or build output.

On iPhone: Settings → General → Keyboard → Keyboards → Add New Keyboard → 言叶, then allow Full Access for sharing dictation results with the containing app. API requests originate only in the main app. Secure fields and apps that disallow third-party keyboards use Apple's keyboard.

## Actual handoff behavior

The central keyboard action resolves the source with the official standalone KeyboardKitHostPlugin11.0.0, writes the single-use ticket, then invokes SwiftUI openURL. Only its public free-to-start bundle-ID resolver is used; no KeyboardKit core, LicenseKit, Pro metadata, or speech engine is linked. The published SHA256 is checked by `scripts/prepare_host_plugin.py`; its offline artifact is ignored by Git. The selected iPhone static library is about75KB before linking. Vendor license is bundled in the extension.

The old MIT arbiter hook received no callbacks on both iOS26.4.1 Simulator and the user's iOS26.6.2 phone and has been removed. The new resolver identifies the actual synthetic fixture correctly. A guarded private captured-bundle resume is attempted, followed by an explicitly supported public resume scheme (currently WeChat). Unknown sources never use a guessed or previously cached app. The simulator uses a separate fixture-only return scheme. Native return success requires observing background state, not merely URL request acceptance or an inactive launch transition. First use of an app link may require a system Open confirmation.

Current verified boundary: simulator keyboard → UtterLeaf → original fixture field round trip passed with real source discovery (`fixtureMatched=true`, `fixedFixture=false`) and preserved text. The user also confirmed return to the original WeChat input field on the physical iPhone. This is not proof of compatibility with every app or conversation. Unsupported sources retain an explicit manual-return path. The Return button exposes pending and concrete failure states.

Once back, stop on the keyboard; processing continues under a bounded iOS background task. Pressing Stop on the keyboard binds the current document/caret as the destination, replacing the proxy captured before the app switch. Completion automatically inserts once if that destination remains unchanged. There is no Insert button. If the input changes during processing, text stays available in the main app and the keyboard waits for the bound input field rather than writing elsewhere. Results expire for insertion after15minutes. A claim recorded before insertion prevents duplicate writes; copying in the app recovers an uncertain terminated insertion. Every Start gets a new request UUID, including after cancellation/failure. Return/Send is never generated.

Five-minute cap, warning at 4:30, cancellation, microphone interruption, slow-network bounds, API timeout and cleanup retry are explicit. Raw text is retained in the running app if cleanup fails; audio is not written to disk. Only the latest result is kept in the App Group; this version has no permanent dictation history. Force-quitting iOS can discard an in-flight recording or raw-only recovery. A terminated active session is marked interrupted on the next app launch.

The private audio/transcript/API-key boundaries are unchanged. No company OpenRouter credentials or billing AK/SK are part of this app.

## Verification

`flutter test` covers UI transitions, cancellation, cleanup recovery, masked key setup and narrow screen layout. Simulator compilation verifies both native targets. Real-device recording, keyboard launch, background processing and insertion are separate acceptance checks; a simulator build is not evidence that these work on a physical iPhone.

Keyboard chrome: `hasDictationKey=true` disables the system dictation button; our Globe appears only when `needsInputModeSwitchKey` requests one. The iOS-owned bottom dock cannot be removed by the extension. The original leaf icon has a full opaque square background so iOS, rather than a nested macOS mask, owns its edge.

Primary references: [Apple custom keyboards](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html), [Flutter app extensions](https://docs.flutter.dev/platform-integration/ios/app-extensions), [Muesli keyboard reference](https://github.com/Muesli-HQ/muesli-ios). The implementation is original; no Muesli source is bundled.

Navigation-only test builds use UTTERLEAF_NAVIGATION_TEST and explicitly disable capture and API calls. This flag is excluded from normal recording-enabled builds. The temporary physical-device test build disables capture/API calls even on a manual app launch, so recording remains unavailable until the normal build is restored. Simulator-only --navigation-fixture is a fixed-target control; it must never be described as successful source discovery. app-navigation.json and keyboard-navigation.json contain only OS/version, availability flags, route, booleans and timestamps, never transcript, audio or credentials.

Simulator delivery verification passed: the real keyboard Stop received a synthetic ready result and automatically appended it exactly once to the original fixture field, without an Insert tap. This verifies keyboard delivery, not real-device ASR completion.

Keyboard refinement (2026-10-27): primary action is a centered200×80pt capsule; the space button is removed, with a44pt delete target and native input-mode switching retained. `--delivery-smoke` is simulator-only: no audio/provider runs. A synthetic provider fixture can publish processing/ready after the real keyboard Stop to verify actual textDocumentProxy insertion independently of ASR/background audio.


Keyboard return actions follow the host field's returnKeyType. Search/Send/Go/Next/Done labels are refreshed on input changes; only an explicit tap inserts the return character. Actual behavior is controlled by the host. Synthetic native Search and Send callback verification passed; dictation completion never submits.

The recording capsule includes a measured-level wave. Simulator maximum/zero scalar controls verify visible amplitude range; real microphone gain still requires user trial. The main Flutter wave uses the same RMS-derived source.

Home / Usage / Settings use a native Liquid Glass navigation surface on iOS26 (system blur fallback on older OS, opaque material with Reduce Transparency). Tab changes preserve capture. Private CloudKit usage synchronization now shares metadata and budgets with the Mac. Source-device filters, known/unknown costs and bounded call details avoid crowding the two rolling allowance bars. Phone usage collection begins with this version; historical phone spend cannot be reconstructed. Never sync local database files wholesale: they contain private text.


### Paid personal team migration · 2026-10-27

The active iOS project now uses the personal Yifan Wang paid team (`2LRMHSV528`), bundle `network.utterleaf.mobile` and keyboard `.keyboard`. These are distinct from the previous free-team bundle, allowing side-by-side rollback without uninstalling user data. The final display name is “言叶” for both app and keyboard; the user confirmed the paid-team WeChat return and automatic insertion, enabled the new keyboard, and removed the old phone app. Enable this new keyboard and grant its Full Access separately; its keys are seeded locally from ignored PersonalKeys.plist into the new team's device-only Keychain. Old app/keychain data is not read or migrated. The new `utterleaf-mobile://` scheme and `group.network.utterleaf.mobile` App Group prevent routing to the old installation.

`python3 scripts/configure_signing.py` regenerates the committed non-secret entitlements for the App Group and `iCloud.network.utterleaf.usage` CloudKit container (retaining the prior container entitlement); no credentials are read. Xcode automatic provisioning registered the container under the paid personal team. The verified new profile has LocalProvision=false, lifetime365days and the intended group/container entitlements. The separate corporate team is not used. `mobile/build/paid-device` holds the new signed artifact; obsolete `personal-device` and `navigation-device` generated builds have been removed at the user’s request.

The Usage screen reads real shared metadata through `CloudUsageSync`, using the same typed model and merge logic as the Mac. Only the main app accesses CloudKit; the keyboard extension has no cloud entitlement. Every-minute foreground sync defers during recording/processing; offline metadata persists, failures preserve cached totals, and account changes block cross-account transfer. A conditional snapshot write merges concurrent edits. `Library/Caches/UsageSync/status.json` is a whitelisted metadata summary with no calls/text/audio/keys/account IDs. `CloudSetup/status.json` remains a separate readiness check. Physical Mac/iPhone bidirectional marker tests and real Mac usage appearing on the phone passed on October28. This is a personal Development build; no production schema deployment or public distribution was attempted.


Navigation motion refinement: one shared native glass selector slides continuously behind the three buttons. Taps spring to the destination; horizontal dragging previews the nearest destination and commits once on release. Cancellation restores the original tab without a Flutter callback. Programmatic selection updates do not echo callbacks. Reduce Motion disables spring/stretch while preserving direct manipulation. Existing recording ownership and native button accessibility remain unchanged. Evaluated [native_glass_navbar](https://github.com/TechSupportz/native_glass_navbar) and [Liquid-Glass-Bar](https://github.com/teiseong/Liquid-Glass-Bar); full UITabBarController embedding was tested but discarded after touch integration failed. The shipped implementation retains the working UIGlassEffect bridge without an added package or copied source.
