# Gym For Teenage

SwiftUI iOS app for locally tracking workouts, body measurements, and water. Project implementation is in progress; all app data stays on device. No account, server, or cloud sync.

## Project

- `GymForTeenage.xcodeproj` — Xcode project (iOS 17+ target).
- `GymForTeenage/GymForTeenageApp.swift` — current SwiftUI app and local data store.
- `GymForTeenageTests` — unit tests.
- `Assets/упражнения` — 15 supplied exercise PNGs.
- `.github/workflows/ios.yml` — macOS CI and unsigned IPA packaging workflow.
- `PRODUCT.md`, `ARCHITECTURE.md`, `ROADMAP.md` — product and implementation specification.

## Build

Open `GymForTeenage.xcodeproj` in Xcode 16 or later and run the `GymForTeenage` scheme on an iOS 17+ simulator. The app uses Apple frameworks only.

## Local data and backup

The app stores a versioned JSON document atomically in Application Support. Backup export/import uses the same versioned DTO; import validates before replacement. A single active workout session is persisted as the user enters data.

## CI and ESign

GitHub Actions runs tests/build on macOS, packages the unsigned app as an IPA-shaped artifact, validates the ZIP and uploads it as `unsigned-ipa-for-esign-validation`. It is explicitly **not represented as install-ready**. The unsigned packaging and actual ESign workflow require validation on a macOS runner and target device. CI contains no user certificate or private key.

## Current implementation coverage

Workout records are analyzed with shared metrics helpers. Statistics include 12-month weight/height trends, separate exercise lines for the latest six records of the selected workout, and a seven-day water bar chart. Active-session edits are written after each state change and the last exercise index is reopened on app launch. JSON import validates before atomic replacement; malformed existing stores are not automatically overwritten.

`GymForTeenageTests` now contains unit and file-backed integration tests. They must run on the configured macOS GitHub Actions runner; this workspace has no Xcode toolchain or Git remote, so no test/build result is claimed here.
