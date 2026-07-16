# CardScanner

An iOS component for scanning Magic: The Gathering cards with the device camera. It reads the **card name**, **set code**, and **collector number** from a physical card and matches the result to an in-app card model.

Built primarily for use in [MTGCards](https://github.com/jmcsmith/MTGCards), but designed as a reusable component.

## Goals

- **Accuracy first** — a scan should resolve to the exact printing (set code + collector number), not just a fuzzy name match.
- **Speed** — live camera recognition with results fast enough for scanning a stack of cards in one session.
- **First-party only** — built on Apple frameworks (AVFoundation, Vision, SwiftUI). No third-party dependencies without explicit sign-off.

## How it works

1. **Capture** — AVFoundation camera session streams frames.
2. **Recognize** — Vision text recognition extracts candidate text regions:
   - Card name from the title line.
   - Set code and collector number from the bottom-left collector info line (e.g. `0123` / `MID`).
3. **Match** — recognized text is normalized and matched against the host app's card database. Collector number + set code is the authoritative key; the card name serves as a cross-check and fallback.

## Requirements

- iOS 26.0+
- Swift 6.2+, strict concurrency
- SwiftUI with `@Observable` state

## Integration

The component exposes a SwiftUI scanning view plus an observable scan result model. The host app (MTGCards) supplies the card lookup, so the scanner stays decoupled from any specific persistence layer.

## Status

Early development — API and structure are still taking shape. See [AGENTS.md](AGENTS.md) for coding conventions used in this repository.
