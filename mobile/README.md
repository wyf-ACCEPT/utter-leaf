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

The central keyboard action is a public SwiftUI `Link`, following the approach used by Muesli's open-source keyboard. Opening the app on a specific iOS release requires device acceptance. This personal-install build attempts a guarded private system Back action after the audio engine starts. If unavailable, a freshly resolved optional host identifier may resume WeChat through its ordinary URL scheme. Unknown hosts and unsupported selectors fall back to the visible manual return prompt; no cached host or arbitrary bundle launch is used. This adapter must be removed or reassessed before public distribution and retested after iOS changes. Automatic return is not guaranteed by Apple. The user can always return manually using the system back affordance or app switcher. Once back, stop on the keyboard; processing continues under a bounded iOS background task. Completion inserts automatically only when the captured document/caret context still matches, otherwise an explicit Insert button is shown. Results expire for insertion after 15 minutes. A claim recorded before insertion prevents duplicate automatic writes; an uncertain terminated insertion is recoverable by copying in the app. Return/Send is never generated.

Five-minute cap, warning at 4:30, cancellation, microphone interruption, slow-network bounds, API timeout and cleanup retry are explicit. Raw text is retained in the running app if cleanup fails; audio is not written to disk. Only the latest result is kept in the App Group; this version has no permanent dictation history. Force-quitting iOS can discard an in-flight recording or raw-only recovery. A terminated active session is marked interrupted on the next app launch.

The private audio/transcript/API-key boundaries are unchanged. No company OpenRouter credentials or billing AK/SK are part of this app.

## Verification

`flutter test` covers UI transitions, cancellation, cleanup recovery, masked key setup and narrow screen layout. Simulator compilation verifies both native targets. Real-device recording, keyboard launch, background processing and insertion are separate acceptance checks; a simulator build is not evidence that these work on a physical iPhone.

Keyboard chrome: `hasDictationKey=true` disables the system dictation button; our Globe appears only when `needsInputModeSwitchKey` requests one. The iOS-owned bottom dock cannot be removed by the extension. The original leaf icon has a full opaque square background so iOS, rather than a nested macOS mask, owns its edge.

Primary references: [Apple custom keyboards](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html), [Flutter app extensions](https://docs.flutter.dev/platform-integration/ios/app-extensions), [Muesli keyboard reference](https://github.com/Muesli-HQ/muesli-ios). The implementation is original; no Muesli source is bundled.
