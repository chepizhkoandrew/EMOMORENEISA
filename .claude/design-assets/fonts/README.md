# Rounded-font stand-ins for design mockups

The app's UI uses iOS's native **SF Pro Rounded** design (`Font.system(design: .rounded)`
in SwiftUI). SF Pro is Apple-licensed and cannot legally be bundled/redistributed as font
files (not in the app bundle, not in this repo, not in a web mockup) — the app already gets
it for free from the OS via the system font API, no files needed there.

For HTML/CSS mockups (Artifacts, browser previews, anything outside an Apple system-font
context), there is no CSS equivalent of `design: .rounded`, so these two open-license
(SIL OFL 1.1) fonts are kept here as visual stand-ins — closest match to SF Pro Rounded's
soft terminals and geometric proportions:

- `Nunito[wght].ttf` — variable weight 200–1000, best all-around match for SF Rounded's warmth.
- `Quicksand[wght].ttf` — variable weight 300–700, rounder/more geometric, good for display text.

`Nunito.b64.txt` / `Quicksand.b64.txt` are pre-computed base64 of the same files, ready to
drop into a `@font-face { src: url(data:font/ttf;base64,...) }` block in a self-contained
HTML artifact (Artifacts' CSP blocks external font requests, so data URIs are required).

Mockups using these should be labeled as an SF Pro Rounded **approximation**, not the real
thing — do not present them as pixel-accurate to the shipped app.

License: both fonts are SIL Open Font License 1.1 (see `OFL-Nunito.txt` / `OFL-Quicksand.txt`),
which permits embedding and redistribution.
