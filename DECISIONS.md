# Decisions

| Date | Decision | Why |
|------|----------|-----|
| 2026-11-04 | Rigor level: real project | Security tool with a signed public release |
| 2026-11-04 | Repository under `williamtrde` | User choice |
| 2026-11-04 | Commits use the GitHub noreply address | A public history should not expose the personal address |
| 2026-11-04 | Postman incident dated October 24, 2026 in the README | Primary source: postmanlabs/postman-app-support#14370, whose log is dated October 24 |
| 2026-11-04 | Severity and recommendation always come from rules, never from the model | A changed file is attacker-controlled input to the model |
| 2026-11-04 | SwiftPM core library + XcodeGen app project | `swift test` stays fast and app-free; Xcode handles universal archive, signing, string catalogs |
| 2026-11-04 | Filtered files never advance their baseline on noise: only the watched-key projection is compared | No disk churn on `~/.claude.json`, and surgical revert stays trivial |
| 2026-11-04 | Damaged `state.json` is moved aside and references are rebuilt from the history; the reset stays visible until acknowledged | Otherwise damaging the state would turn a modified file into its own reference |
| 2026-11-04 | Decisions carry the fingerprint of the change the user saw; a mismatch opens the window instead of deciding | A newer change must never be accepted unseen |
| 2026-11-04 | For critical changes, "What changed" always comes from the rules, the model only phrases the impact | The model misread a diff during the demo, and this sentence is also the notification |
| 2026-11-04 | A pause only shows the paused icon when nothing is pending | Spec item 1: a pending critical change must stay visible |
| 2026-11-04 | README cites the Postman case as a public report and links it; the MCP redirect scenario names nobody | Only what could be checked at a primary source is attributed |
| 2026-11-04 | Surgical revert keeps values but rewrites the file: comments and formatting of filtered files can change, a backup is saved first | A text-level patch is a large new write path; the README says so plainly. Deviation from the spec's "preserves the rest of the file", to validate |
| 2026-11-04 | INBOX.md stays local and out of the public repository | Personal working notes |
