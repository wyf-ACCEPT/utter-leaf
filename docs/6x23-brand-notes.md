# UtterLeaf identity · 2026-10-23

Design workflow: installed Logo Designer 1.2.0 `logo-designer`, `logo-svg` and `app-icon-favicon` skills. This is a code-native vector design, not an external hosted logo-generation service. No audio, transcript or credential was sent for branding.

## Brief and selected concept

UtterLeaf（言叶）is a private macOS dictation app for Jason Wang. Personality: quiet, fluent, personal. User selected **A: 言叶** on 2026-10-23. A tapered leaf becomes a speech bubble; the negative-space vein bends into a short spoken waveform. It stays recognisable without letters.

| Concept | Type / shapes | Palette | Typography | Layout and fit |
|---|---|---|---|---|
| A · 言叶 (selected) | Symbol + wordmark. Single leaf/bubble silhouette and one broad waveform cutout. | Forest #14241D, leaf #A6D7B8, light green #2D5E46 | Native SF Pro Rounded / PingFang SC; free alternatives Nunito Sans and Noto Sans SC | Icon left or above. Connects voice, words and the product name. |
| B · 叶声 | Abstract symbol. Three leaves of increasing height form an audio waveform. | Green #A6D7B8, ink #141C18 | Free alternatives Manrope and Noto Sans SC | Icon left. More directly an audio tool; weaker speech metaphor. |
| C · UL | Lettermark. A continuous U turns into a lower L baseline. | Green #A6D7B8, ink #141C18 | Free alternatives Plus Jakarta Sans and Noto Sans SC | Compact monogram. Good utility symbol, less specific to Chinese name. |

Concept board: `assets/brand/concepts.svg`.

## Files and reproducibility

- `utterleaf-app-icon.svg`: 1024-square vector master, native macOS safe margin.
- `utterleaf-app-icon.png`, `utterleaf-app-icon-light.png`: dark/light raster masters.
- `UtterLeaf.icns`: multiresolution native application icon.
- `utterleaf-mark-light.svg`, `utterleaf-mark-dark.svg`: transparent symbol variants.
- `utterleaf-mark-mono.svg`, `utterleaf-mark-reversed.svg`: single-color variants.
- `utterleaf-horizontal.svg`, `utterleaf-stacked.svg`: wordmark lockups. Text uses font stacks; convert text to outlines before handing to a print vendor.
- `favicon.svg`: scalable small icon. App iconset includes 16/32/64/128/256/512/1024 representations.
- `scripts/render-brand.swift`: AppKit vector-to-PNG rendering with the same geometry as `LeafMark` in the UI.

No image generator is required for the vector master. Meaning is carried by silhouette and a broad cutout, not gradient, thin detail or text. No trademark clearance has been performed.

## Optional image prompts

A: Original flat vector icon for UtterLeaf, a private macOS dictation app. One diagonal leaf silhouette integrated with a speech-bubble tail, a broad negative-space vein bending into a short voice wave. Botanical pale green on deep forest, no text, no gradient, strong at 16px, centered square safe area. Do not imitate any existing logo.

B: Original flat vector mark, three thick leaves of increasing height forming an audio waveform for UtterLeaf. Botanical green, charcoal forest, no microphone illustration, no lettering, no fine detail, balanced square composition.

C: Original monoline-independent geometric UL lettermark for UtterLeaf, U turning into an L baseline like a small sprout. Use filled shapes, strong negative space, pale green on deep forest, no gradient, no fine detail.
