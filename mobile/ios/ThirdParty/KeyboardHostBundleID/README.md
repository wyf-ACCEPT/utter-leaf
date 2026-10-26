# KeyboardHostBundleID arbiter adapter

Vendored Objective-C hook only from https://github.com/Muskupecli/KeyboardHostBundleID (MIT, copyright2026 editorss). No binary SDK or network dependency. Used only in the personal keyboard extension to identify the current host on iOS26.4+. Source performs local UIKit runtime interception, not OS-wide injection. Reassess before public distribution. Keep the LICENSE in the shipped extension resources.

The app wrapper accepts only a capture newer than the current tap, clears on disappearance, and never falls back to an earlier app. No typed text, audio, keys or external telemetry enter the resolver. The user requested automatic return to the originating app. This is not a stable public API.
f1106dd9f1f09e01c9c28e10e2882990bb14acdc

Local changes: added a content-free diagnostic availability accessor. Runtime tests on iOS26.4.1 Simulator currently receive no arbiter callbacks despite class/method/client availability; do not represent deterministic mocked tests as end-to-end host resolution. Fresh-only resolution deliberately returns nil instead of choosing a cached previous app.
