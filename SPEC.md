# Warden: specification

Rigor level: **real project** (full method: per-task loop, independent reviewer every 3 to 5 tasks and at the end).

## What we are building
A native macOS menu bar app that watches the config files of AI coding agents (Claude Code, Codex, Cursor), detects silent changes, classifies their risk, and explains in plain language what each change means for the projects the person actually works on. Explanations come from Apple's on-device model (Foundation Models) with a rule-based fallback. Target: people who let agents run autonomously and never read their config files.

## V1 scope

### Included
1. Menu bar icon, no Dock icon, 3 states: green (compliant), orange (pending change), red (pending critical change).
2. Real-time FSEvents monitoring of 8 default files, when they exist; user can add or remove files.
3. Baseline on first launch: copy + SHA-256 per file. Every accepted version joins a history.
4. Diff and classification. CRITICAL rules (isolated, extensible module):
   hooks; MCP server added or its URL, command, args or env changed (top level and per project); sensitive env vars (ANTHROPIC_BASE_URL, OPENAI_BASE_URL, proxies, apiKeyHelper, otelHeadersHelper); enableAllProjectMcpServers; permission widening (bypass, allow on Bash or network); new plugins or marketplaces; Codex hook trust hashes; project trust flags.
5. Usage context from metadata only: known projects in ~/.claude.json (keys only), folder names and mtimes in ~/.claude/projects, Codex and Cursor equivalents. Active = used in the last 14 days. Session or conversation content is never read; enforced by test.
6. Personalized explanation in 2 to 4 sentences: what changed, what it means for you (projects, agents), what Warden recommends. Foundation Models when available; built-in rules otherwise. Secrets masked before the model sees the diff. Source shown discreetly ("On-device AI" or "Built-in rules"). System language (en, fr at minimum).
7. Native notification with file, severity, first sentence, and Accept / Revert actions.
8. Main window: watched files with status; explanation on top; coloured diff with critical lines highlighted; Accept / Revert (backup before overwrite); chronological history with restore of any past version.
9. Settings: launch at login (SMAppService), watched files, pause, disable on-device AI.

### Noise policy (user decision)
Per-file watch policy, centralized in one module and documented in the README ("What triggers an alert" table).
- **Filtered files** (`~/.claude.json`, Cursor `User/settings.json`): only security-relevant keys alert. Everything else is absorbed silently into the baseline.
  - `~/.claude.json`: `mcpServers`, `env`, `hooks`, `permissions`, trust flags and tool allowances, at top level and inside every `projects.<path>` (`mcpServers`, `enabledMcpjsonServers`, `disabledMcpjsonServers`, `hasTrustDialogAccepted`, `allowedTools`, ...). Any change to an MCP server URL, command or env is CRITICAL.
  - Cursor `settings.json`: only keys related to AI, agents, MCP and the terminal.
  - Revert on a filtered file is **surgical**: it restores the watched keys only and preserves the rest of the file.
  - Test: 100 routine Claude Code writes to `~/.claude.json` produce zero alerts.
- **All other files** (`settings.json`, `settings.local.json`, `config.toml`, `CLAUDE.md`, `AGENTS.md`, `mcp.json`, user-added files): every change alerts, Revert restores the whole file.

### Instruction files (user decision)
`CLAUDE.md`, `AGENTS.md` are INFO by default. A plain shell command or URL stays INFO, but is highlighted in the diff and mentioned in the explanation. CRITICAL only for: invisible or deceptive text (hidden Unicode, zero-width, bidi override, HTML comments); bypass instructions (ignore previous instructions, do not ask for confirmation, auto-approve, hide an action from the user); remote code download and execution (curl or wget piped to a shell or interpreter); reading or sending secrets, or sending data to an external URL; long encoded strings of unreadable meaning. Each pattern lives in the rules module with its own plain-language explanation and tests (one must fire, one legitimate case must not).

### Excluded (V2 or never)
Identifying the writing app (Endpoint Security), blocking writes, reading session content or project code, cloud AI, Windows, Linux, Mac App Store, Sparkle, accounts, sync, per-repo config files.

## Security invariants
- Automatic revert never happens. The user always decides.
- No network: no networking API in the code base, verified by a test scanning sources; no network entitlement applies since the app is unsandboxed, so this is a code-level guarantee.
- A changed file is attacker-controlled input to the model. **Severity and recommendation are computed by the rules, never by the model.** The model only phrases the explanation; its output is validated and discarded for the fallback if invalid.
- Secrets are masked before reaching the model, and in everything Warden displays.
- Baseline copies live in `~/Library/Application Support/Warden/` with 0700 / 0600 permissions, because they contain whatever the originals contain.

## Stack
Swift 5.9+ language mode, SwiftUI `MenuBarExtra`, macOS 14 minimum, universal binary. `FoundationModels` is weak-linked and gated by `#available` plus a runtime availability check. No third-party runtime dependency (small in-house TOML and JSONC readers). Dev tools only: XcodeGen, SwiftLint. Hardened Runtime, no App Sandbox.

## Structure
```
Package.swift                 WardenCore library + XCTest suite
Sources/WardenCore/
  Model/         shared types
  Watching/      FSEvents wrapper
  Parsing/       JSON, JSONC, TOML to flat key paths
  Diff/          line diff, structural diff
  Policy/        per-file watch policy (single source of truth)
  Risk/          rules engine, config rules, instruction rules
  Usage/         metadata-only usage context
  Redaction/     secret masking
  Explanation/   ExplanationGenerator protocol, on-device, fallback
  Storage/       baseline, versions, history, restore
  Engine/        orchestration
App/                          SwiftUI app, Info.plist, entitlements, assets, string catalog
project.yml                   XcodeGen definition
scripts/                      build, sign, notarize, DMG, demo
.github/workflows/ci.yml      build + tests on every push, unsigned
```

## Run and test
- `swift test`: full logic suite, never touches real user files (injected home directory).
- `scripts/build-app.sh`: Release universal app.
- `scripts/release.sh`: sign, notarize (`--keychain-profile warden-notary`), staple, DMG.
- `scripts/demo.sh`: safe demo against a sandboxed fake home.

## Delivery
Public repository `williamtrde/warden`, MIT, topics, polished English README, CI badge, release v1.0.0 with the notarized DMG.
