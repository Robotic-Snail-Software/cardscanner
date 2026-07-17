# CardScanner

A Swift package for scanning Magic: The Gathering cards with the iPhone camera. It reads the **card name**, **set code**, and **collector number** from a physical card, verifies them against the host app's card catalog, and delivers a confirmed printing.

Built primarily for [MyMTG](https://github.com/jmcsmith/MyMTG), but decoupled from any specific persistence layer.

## Goals

- **Accuracy first** — a scan resolves to the exact printing (set code + collector number), verified against the catalog, with the OCR'd name as a cross-check. A set code is never reported without a collector number, and misreads decay away instead of locking.
- **Speed** — continuous live scanning with temporal vote stabilization; a steady card locks in roughly 1–2 seconds, and auto-resume makes scanning a stack fast.
- **First-party only** — AVFoundation, Vision, SwiftUI. No third-party dependencies.

## How it works

```
Camera (AVFoundation, near-focus AF, latest-frame-only stream)
  → RecognitionEngine (2 ROI-restricted Vision text requests per frame:
      title band + collector band)
  → CollectorLineParser (regex ladder + validity gates, OCR digit repair)
  → ObservationAccumulator (exponential-decay voting across frames)
  → ScanResolver (lock rules, catalog-verified)
  → ScannedCard → host
```

Three lock levels, strictest first:

| Confidence | Meaning |
|---|---|
| `.exactPrinting` | Set + number resolved in the catalog **and** the OCR name agrees |
| `.printingOnly` | Set + number resolved, no usable name read (higher evidence bar) |
| `.nameOnly` | No collector line (older frames); near-exact name match with clear margin, `alternates` carries the candidate printings |

## Usage

```swift
import CardScanner

// 1. Implement CardCatalog over your card store.
struct MyCatalog: CardCatalog {
    func printing(setCode: String, collectorNumber: String) async throws -> CatalogPrinting? {
        // Exact lookup — setCode is UPPERCASE, collectorNumber has leading
        // zeros stripped and suffixes preserved ("118a"), matching MTGJSON.
    }
    func candidates(forName name: String, limit: Int) async throws -> [CatalogPrinting] {
        // Loose name search; the scanner ranks by edit-distance similarity.
        // Tip: search by the longest word of `name` — OCR-damaged readings
        // still hit, and the scanner's matcher does the precise ranking.
    }
}

// 2. Create the model, receive locked cards, present the view.
let model = CardScannerModel(catalog: MyCatalog())
model.onCardLocked = { scanned in
    // scanned.catalogID is your CatalogPrinting.id — resolve and save.
}

CardScannerView(model: model)   // starts/stops the camera with its lifecycle
```

The host app must include `NSCameraUsageDescription` in its Info.plist.

`ScannerConfiguration` exposes the lock thresholds, decay half-life, and `autoResume` (default: resume ~1.2 s after each lock for stack scanning; use `.manual` for confirm-per-card).

## Example app

`Example/CardScannerDemo.xcodeproj` is a minimal harness for on-device tuning (the camera requires real hardware — set your signing team before running). Its in-memory catalog seeds a few well-known card names for name-only matching and learns exact printings live: point the scanner at any card and tap **Trust Reading** to add what was read, after which subsequent scans of that card lock as `.exactPrinting`.

## Requirements

- iOS 26.0+
- Swift 6.2, strict concurrency, `MainActor` default isolation
- SwiftUI with `@Observable`

## Development

```sh
xcodebuild test -scheme CardScanner -destination 'platform=iOS Simulator,name=iPhone 17'
```

The parsing, matching, stabilization, and geometry layers are pure and fully unit-tested (no camera needed). See [AGENTS.md](AGENTS.md) for coding conventions.
