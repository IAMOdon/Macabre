# Macabre

A watchOS app that turns your heart rate into a memento mori: it estimates how
many heartbeats you have left (from average life expectancy) and counts them
down **live**, beat by beat, using HealthKit. It ships with a companion
complication so the number is always on your watch face.

> ⌚️ Built for Apple Watch (Ultra 3 / 49 mm layout), watchOS 26+.

---

## Features

- **Live heartbeat countdown** — decrements every second at your current BPM,
  falling back to a rolling average when no live reading is available.
- **Heart-rate insights** — a live BPM chart with min / average / max.
- **Time breakdown** — the remaining beats expressed as years / days / hours /
  minutes / seconds.
- **Complications** — rectangular, inline, and corner accessory families.
- **Offline-correct** — when the app is suspended, it reconciles the count
  against the heart rate HealthKit actually recorded while you were away, so the
  number stays honest without draining the battery in the background.

## Architecture

```
Macabre Watch App/      SwiftUI screens + the RealHealthManager view model
Macabre Watch Widget/   WidgetKit complications + timeline provider
Shared/                 HeartbeatMath.swift — logic both targets share
Macabre Watch AppTests/ Unit tests for the shared logic
```

- **`Shared/HeartbeatMath.swift`** is the single source of truth for the pure,
  deterministic logic: tuning constants and App-Group keys
  (`MacabreConstants`), the beats → time breakdown (`HeartbeatTime`), the
  offline catch-up accounting (`CatchUp`), and the HealthKit dependency seam
  (`HeartRateProviding` / `HealthKitHeartRateProvider`). It is compiled into
  both the app and the widget so they can never drift apart.
- **`RealHealthManager`** is a `@MainActor` `ObservableObject` view model. It
  receives heart-rate data through the injected `HeartRateProviding`, so it is
  testable without HealthKit (see `PreviewHeartRateProvider` and the tests).
- HealthKit access is async/await throughout; there is no background "keep
  alive" hack — the per-second tick suspends with the app and the count is
  reconciled on resume.

## Requirements

- Xcode 26 or later
- watchOS 26 SDK
- An Apple Watch with a heart-rate sensor (HealthKit is not available in most
  simulators, so live data needs a real device)

## Building

This project uses your own Apple developer identity and a private App Group.
Before it will build and run on a device you must change a few values to your
own:

1. **Signing** — open `Macabre.xcodeproj`, select each target, and set your
   own **Team** under *Signing & Capabilities*. (The committed
   `DEVELOPMENT_TEAM` and `armandwegnez.*` bundle identifiers are placeholders.)
2. **App Group** — pick your own group id (e.g. `group.<you>.Macabre`) and
   update it in **all three** places so the app and widget share data:
   - `Shared/HeartbeatMath.swift` → `MacabreConstants.appGroupSuiteName`
   - `Macabre Watch App/Macabre Watch App.entitlements`
   - `Macabre Watch Widget/Macabre Watch Widget.entitlements`
3. Build the **Macabre Watch App** scheme to a device or simulator.

To run the unit tests:

```sh
xcodebuild test \
  -project Macabre.xcodeproj \
  -scheme Macabre \
  -destination 'platform=watchOS Simulator,name=Apple Watch Ultra 3 (49mm)' \
  -only-testing:"Macabre Watch AppTests"
```

## Privacy

Macabre only **reads** your heart rate from HealthKit, on-device. It writes
nothing to HealthKit and sends nothing off the watch.

## Known limitations / good first issues

- **No birthday input yet.** The starting beat count is seeded from a neutral
  placeholder age (`MacabreConstants.defaultAgeYears`). A small settings screen
  that lets the user set their date of birth (persisted under the existing
  `BirthDate` key) would make the count personal.
- **Localization.** The UI strings are currently French only.
- **Swift 6 strict concurrency.** The code uses structured concurrency and is
  `@MainActor`-isolated, but the project still builds in the Swift 5 language
  mode; adopting full Swift 6 strict-concurrency checking is a worthwhile
  follow-up (the main friction is HealthKit's non-`Sendable` query objects).

## License

[MIT](LICENSE) © Armand Wegnez
