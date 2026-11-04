# Decisions

| Date | Decision | Why |
|------|----------|-----|
| 2026-11-04 | Rigor level: real project | Portfolio centerpiece, security tool, signed release |
| 2026-11-04 | Repository under `williamtrde` | User choice |
| 2026-11-04 | Commits use the GitHub noreply address | A public history should not expose the personal address |
| 2026-11-04 | Postman incident dated October 24, 2026 in the README | Primary source: issue #14370, the brief said November |
| 2026-11-04 | Severity and recommendation always come from rules, never from the model | A changed file is attacker-controlled input to the model |
| 2026-11-04 | SwiftPM core library + XcodeGen app project | `swift test` stays fast and app-free; Xcode handles universal archive, signing, string catalogs |
| 2026-11-04 | Filtered files never advance their baseline on noise: only the watched-key projection is compared | No disk churn on `~/.claude.json`, and surgical revert stays trivial |
