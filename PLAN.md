# Warden: plan

Each task follows the loop: implement, test, `swift test` + build + `swiftlint` green, self-review, commit, update PROGRESS.md.

| # | Task | Validation |
|---|------|------------|
| 1 | Scaffold: Package.swift, SwiftLint, CI, MIT license, gitignore | `swift build` + `swiftlint` pass |
| 2 | Model + parsers (JSON, JSONC, minimal TOML) | Parser tests incl. Postman `config.toml` |
| 3 | Diff: line diff with hunks, structural leaf-level diff | Diff tests |
| 4 | Policy: watch catalog, key patterns, filtering, projection | 100 routine writes produce zero relevant changes |
| 5 | Risk: config rules | One test per critical rule, Postman and Mitiga fixtures |
| 6 | Risk: instruction-file rules | Fire + legit case per pattern |
| R1 | Independent review of tasks 2 to 6 | Severe findings fixed |
| 7 | Redaction | Secrets never survive; stable markers keep changes visible |
| 8 | Usage context, metadata only | Unreadable session files + spy prove no content read |
| 9 | Fallback explanations en + fr | One test per rule per language |
| 10 | On-device generator, validator, composite with timeout | Mock model: injection, invalid output, timeout all fall back |
| 11 | Storage: versions, baseline, history, atomic restore, surgical revert | Restore tests |
| 12 | FSEvents watcher | Integration test with atomic rename in temp dir |
| 13 | Engine orchestration | End-to-end tests with fake watcher |
| R2 | Independent review of tasks 7 to 13 | Severe findings fixed |
| 14 | App shell: XcodeGen, MenuBarExtra, 3 icon states, no Dock icon | App builds and launches |
| 15 | Notifications with Accept and Revert | Category registered, actions routed |
| 16 | Main window: files, explanation, diff, actions, history | Runs against demo home |
| 17 | Settings, launch at login, en + fr string catalog | Both languages render |
| R3 | Independent review of the app layer | Severe findings fixed |
| 18 | Demo script, app icon, screenshots, GIF | Assets in docs/ |
| 19 | README, CONTRIBUTING | README table guarded by test |
| 20 | Release script: archive, sign, notarize, staple, DMG | `spctl` + `stapler validate` pass |
| R4 | Final independent review + full verification | All green |
| 21 | Publish repo, topics, release v1.0.0 | CI green on GitHub, DMG attached |
